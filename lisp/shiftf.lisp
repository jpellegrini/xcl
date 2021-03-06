;;; shiftf.lisp

;; Copyright (C) 2002-2004, Yuji Minejima <ggb01164@nifty.ne.jp>
;; ALL RIGHTS RESERVED.
;;
;; $Id: data-and-control.lisp,v 1.17 2004/09/02 06:59:43 yuji Exp $
;;
;; Redistribution and use in source and binary forms, with or without
;; modification, are permitted provided that the following conditions
;; are met:
;;
;;  * Redistributions of source code must retain the above copyright
;;    notice, this list of conditions and the following disclaimer.
;;  * Redistributions in binary form must reproduce the above copyright
;;    notice, this list of conditions and the following disclaimer in
;;    the documentation and/or other materials provided with the
;;    distribution.
;;
;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
;; A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
;; OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
;; SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
;; LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
;; DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
;; THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
;; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
;; OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

(in-package "SYSTEM")

(defmacro shiftf (&rest places-and-newvalue &environment env)
  (let ((nargs (length places-and-newvalue)))
;;     (assert (>= nargs 2))
    (unless (>= nargs 2)
      (error 'program-error
             :format-control "Wrong number of arguments for ~S (expected at least 2, but received %D)."
             :format-arguments (list 'shiftf nargs)))
    (let ((place (car places-and-newvalue)))
      (multiple-value-bind (temps vars newvals setter getter)
	  (get-setf-expansion place env)
	`(let (,@(mapcar #'list temps vars))
	   (multiple-value-prog1 ,getter
	     (multiple-value-bind ,newvals
		 ,(if (= nargs 2)
		      (cadr places-and-newvalue)
		    `(shiftf ,@(cdr places-and-newvalue)))
	       ,setter)))))))
