;;; p2-arith.lisp
;;;
;;; Copyright (C) 2006-2011 Peter Graves <gnooth@gmail.com>
;;;
;;; This program is free software; you can redistribute it and/or
;;; modify it under the terms of the GNU General Public License
;;; as published by the Free Software Foundation; either version 2
;;; of the License, or (at your option) any later version.
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with this program; if not, write to the Free Software
;;; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

(in-package "COMPILER")

(defknown numeric-but-not-fixnum-type-p (t) t)
(defun numeric-but-not-fixnum-type-p (type)
  (cond ((eq type :unknown)
         nil)
        ((subtypep type 'float)
         t)
        ((subtypep type 'ratio)
         t)
        ((subtypep type 'bignum)
         t)
        ((subtypep type 'complex)
         t)))

(defknown p2-two-arg-+ (t t) t)
(defun p2-two-arg-+ (form target)
  (when (check-arg-count form 2)
    (let* ((args (%cdr form))
           (arg1 (%car args))
           (arg2 (%cadr args))
           (type1 (derive-type arg1))
           (type2 (derive-type arg2))
           (result-type (derive-type form)))
      (unless (fixnump arg1)
        (when (and (integer-constant-value type1)
                   (flushable arg1))
          (setq arg1 (integer-constant-value type1))))
      (unless (fixnump arg2)
        (when (and (integer-constant-value type2)
                   (flushable arg2))
          (setq arg2 (integer-constant-value type2))))
      (when (and (numberp arg1)
                 (numberp arg2))
        (p2-constant (two-arg-+ arg1 arg2) target)
        (return-from p2-two-arg-+ t))
      (when (fixnump arg1)
        (psetq arg1  arg2
               arg2  arg1
               type1 type2
               type2 type1)
        (setq args (list arg1 arg2)))
      (cond ((eql arg2 0)
             (process-1-arg arg1 target t))
            ((or (numeric-but-not-fixnum-type-p type1)
                 (numeric-but-not-fixnum-type-p type2))
             (process-2-args args :default t)
             (emit-call-2 'two-arg-+ target))
            ((and (fixnump arg2)
                  (typep (fixnumize arg2) '(signed-byte 32)))
             (let* ((FULL-CALL (make-label))
                    (FIX-OVERFLOW (make-label))
                    (EXIT (make-label))
                    (reg (if (register-p target) target $ax)))
               (process-1-arg arg1 reg t)
               (unless (fixnum-type-p type1)
                 (inst :test +fixnum-tag-mask+ (reg8 reg))
                 (emit-jmp-short :nz FULL-CALL))
               (inst :add (fixnumize arg2) reg)
               (clear-register-contents reg)
               (unless (fixnum-type-p result-type)
                 (emit-jmp-short :o FIX-OVERFLOW))
               (label EXIT)
               (unless (eq reg target)
                 (move-result-to-target target))
               (unless (fixnum-type-p type1)
                 (clear-register-contents)
                 (let ((*current-segment* :elsewhere))
                   (label FULL-CALL)
                   (clear-register-contents)
                   #+x86    (progn
                              (inst :push (fixnumize arg2))
                              (inst :push reg))
                   #+x86-64 (progn
                              (unless (eq reg :rdi)
                                (inst :mov reg :rdi))
                              (inst :mov (fixnumize arg2) :rsi))
                   (emit-call 'two-arg-+)
                   #+x86 (inst :add (* +bytes-per-word+ 2) :esp)
                   (unless (eq reg $ax)
                     (inst :mov $ax reg))
                   (emit-jmp-short t EXIT)))
               (unless (fixnum-type-p result-type)
                 (clear-register-contents)
                 (let ((*current-segment* :elsewhere))
                   (label FIX-OVERFLOW)
                   (unbox-fixnum reg)
                   #+x86    (inst :push reg)
                   #+x86-64 (unless (eq reg :rdi)
                              (inst :mov reg :rdi))
                   (emit-call "RT_fix_overflow")
                   #+x86    (inst :add +bytes-per-word+ :esp)
                   (unless (eq reg $ax)
                     (inst :mov $ax reg))
                   (emit-jmp-short t EXIT)))))
            ((and (fixnum-type-p type1) (fixnum-type-p type2) (fixnum-type-p result-type))
             (let (reg1 reg2)
               (cond ((register-p target)
                      (setq reg2 target))
                     (t
                      (setq reg2 $ax)))
               (setq reg1 (if (eql reg2 $ax) $dx $ax))
               (process-2-args args `(,reg1 ,reg2) t)
               (inst :add reg1 reg2)
               (clear-register-contents reg2)
               (unless (eq reg2 target)
                 (aver (eq reg2 $ax))
                 (move-result-to-target target))))
            (t
             (let ((FULL-CALL (make-label))
                   (FIX-OVERFLOW (make-label))
                   (EXIT (make-label)))
               (process-2-args args `(,$ax ,$dx) t)
               (unless (fixnum-type-p type1)
                 (inst :test +fixnum-tag-mask+ :al)
                 (emit-jmp-short :nz FULL-CALL))
               (unless (fixnum-type-p type2)
                 (inst :test +fixnum-tag-mask+ :dl)
                 (emit-jmp-short :nz FULL-CALL))
               ;; falling through, both args are fixnums
               (inst :add $dx $ax)
               (clear-register-contents $ax)
               (unless (fixnum-type-p result-type)
                 (emit-jmp-short :o FIX-OVERFLOW))
               (label EXIT)
               (move-result-to-target target)
               (unless (and (fixnum-type-p type1) (fixnum-type-p type2))
                 (clear-register-contents)
                 (let ((*current-segment* :elsewhere))
                   (label FULL-CALL)
                   #+x86    (progn
                              (inst :push :edx)
                              (inst :push :eax))
                   #+x86-64 (progn
                              (inst :mov :rdx :rsi)
                              (inst :mov :rax :rdi))
                   (emit-call 'two-arg-+)
                   #+x86    (inst :add (* +bytes-per-word+ 2) :esp)
                   (emit-jmp-short t EXIT)))
               (unless (fixnum-type-p result-type)
                 (clear-register-contents)
                 (let ((*current-segment* :elsewhere))
                   (label FIX-OVERFLOW)
                   (unbox-fixnum $ax)
                   #+x86    (inst :push :eax)
                   #+x86-64 (inst :mov :rax :rdi)
                   (emit-call "RT_fix_overflow")
                   #+x86    (inst :add +bytes-per-word+ :esp)
                   (emit-jmp-short t EXIT)))
               ))))
    t))

(defknown p2-two-arg-- (t t) t)
#+x86-64
(defun p2-two-arg-- (form target)
  (mumble "p2-two-arg-- new code~%")
  (when (check-arg-count form 2)
    (let* ((args (%cdr form))
           (arg1 (%car args))
           (arg2 (%cadr args))
           (type1 (derive-type arg1))
           (type2 (derive-type arg2))
           (result-type (derive-type form)))
      (unless (fixnump arg1)
        (when (and (integer-constant-value type1)
                   (flushable arg1))
          (setq arg1 (integer-constant-value type1))))
      (unless (fixnump arg2)
        (when (and (integer-constant-value type2)
                   (flushable arg2))
          (setq arg2 (integer-constant-value type2))))
      (when (and (numberp arg1)
                 (numberp arg2))
        (mumble "p2-two-arg-- case 0~%")
        (p2-constant (two-arg-- arg1 arg2) target)
        (return-from p2-two-arg-- t))
      (cond ((eql arg2 0)
             (mumble "p2-two-arg-- case 1a~%")
             (process-1-arg arg1 target t))
            ((and (eql arg1 0) (fixnum-type-p type2) (fixnum-type-p result-type))
             (mumble "p2-two-arg-- case 1b~%")
             (let ((reg (if (register-p target) target $ax)))
               (process-1-arg arg2 reg t)
               (inst :neg reg)
               (unless (eq target reg)
                 (move-result-to-target target))))
            ((or (numeric-but-not-fixnum-type-p type1)
                 (numeric-but-not-fixnum-type-p type2))
             (mumble "p2-two-arg-- case 2~%")
             (process-2-args args :default t)
             (emit-call-2 'two-arg-- target))
            ((and (fixnump arg2)
                  (typep (fixnumize arg2) '(signed-byte 32)))
             (mumble "p2-two-arg-- case 3~%")
             (let* ((FULL-CALL (make-label))
                    (FIX-OVERFLOW (make-label))
                    (EXIT (make-label))
                    (reg (if (register-p target) target $ax)))
               (process-1-arg arg1 reg t)
               (unless (fixnum-type-p type1)
                 (inst :test +fixnum-tag-mask+ (reg8 reg))
                 (emit-jmp-short :nz FULL-CALL))
               (inst :sub (fixnumize arg2) reg)
               (clear-register-contents reg)
               (unless (fixnum-type-p result-type)
                 (emit-jmp-short :o FIX-OVERFLOW))
               (label EXIT)
               (unless (eq reg target)
                 (move-result-to-target target))
               (unless (fixnum-type-p type1)
                 (clear-register-contents)
                 (let ((*current-segment* :elsewhere))
                   (label FULL-CALL)
                   (clear-register-contents)
                   #+x86    (progn
                              (inst :push (fixnumize arg2))
                              (inst :push reg))
                   #+x86-64 (progn
                              (unless (eq reg :rdi)
                                (inst :mov reg :rdi))
                              (inst :mov (fixnumize arg2) :rsi))
                   (emit-call 'two-arg--)
                   #+x86 (inst :add (* +bytes-per-word+ 2) :esp)
                   (unless (eq reg $ax)
                     (inst :mov $ax reg))
                   (emit-jmp-short t EXIT)))
               (unless (fixnum-type-p result-type)
                 (clear-register-contents)
                 (let ((*current-segment* :elsewhere))
                   (label FIX-OVERFLOW)
                   (unbox-fixnum reg)
                   #+x86    (inst :push reg)
                   #+x86-64 (unless (eq reg :rdi)
                              (inst :mov reg :rdi))
                   (emit-call "RT_fix_overflow")
                   #+x86    (inst :add +bytes-per-word+ :esp)
                   (unless (eq reg $ax)
                     (inst :mov $ax reg))
                   (emit-jmp-short t EXIT)))))
            ((and (fixnum-type-p type1) (fixnum-type-p type2) (fixnum-type-p result-type))
             (mumble "p2-two-arg-- case 4 target = ~S~%" target)
             (let (reg1 reg2)
               (cond ((register-p target)
                      (setq reg1 target))
                     (t
                      (setq reg1 $ax)))
               (setq reg2 (if (eql reg1 $ax) $dx $ax))
               (process-2-args args `(,reg1 ,reg2) t)
               (inst :sub reg2 reg1)
               (clear-register-contents reg1)
               (unless (eq reg1 target)
                 (aver (eq reg1 $ax))
                 (move-result-to-target target))))
            (t
             (mumble "p2-two-arg-- case 5~%")
             (let ((FULL-CALL (make-label))
                   (FIX-OVERFLOW (make-label))
                   (EXIT (make-label)))
               (process-2-args args `(,$ax ,$dx) t)
               (unless (fixnum-type-p type1)
                 (inst :test +fixnum-tag-mask+ :al)
                 (emit-jmp-short :nz FULL-CALL))
               (unless (fixnum-type-p type2)
                 (inst :test +fixnum-tag-mask+ :dl)
                 (emit-jmp-short :nz FULL-CALL))
               ;; falling through, both args are fixnums
               (inst :sub $dx $ax)
               (clear-register-contents $ax)
               (unless (fixnum-type-p result-type)
                 (emit-jmp-short :o FIX-OVERFLOW))
               (label EXIT)
               (move-result-to-target target)
               (unless (and (fixnum-type-p type1) (fixnum-type-p type2))
                 (clear-register-contents)
                 (let ((*current-segment* :elsewhere))
                   (label FULL-CALL)
                   #+x86    (progn
                              (inst :push :edx)
                              (inst :push :eax))
                   #+x86-64 (progn
                              (inst :mov :rdx :rsi)
                              (inst :mov :rax :rdi))
                   (emit-call 'two-arg--)
                   #+x86    (inst :add (* +bytes-per-word+ 2) :esp)
                   (emit-jmp-short t EXIT)))
               (unless (fixnum-type-p result-type)
                 (clear-register-contents)
                 (let ((*current-segment* :elsewhere))
                   (label FIX-OVERFLOW)
                   (unbox-fixnum $ax)
                   #+x86    (inst :push :eax)
                   #+x86-64 (inst :mov :rax :rdi)
                   (emit-call "RT_fix_overflow")
                   #+x86    (inst :add +bytes-per-word+ :esp)
                   (emit-jmp-short t EXIT)))
               ))))
    t))
