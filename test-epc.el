;;; test-epc.el --- test code for epc

;; Copyright (C) 2011  SAKURAI Masashi
;; Author: SAKURAI Masashi <m.sakurai at kiwanami.net>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Run tests:
;; $ emacs -L . -L $HOME/.emacs.d/elisp -batch -l deferred -l concurrent -l epc -l epcs -l test-epc -f ert-run-tests-batch-and-exit

;;; Code:

(require 'epc)
(require 'epcs)
(require 'cl)
(require 'pp)


(defvar epc:source-dir (if load-file-name
                           (file-name-directory load-file-name)
                         default-directory))

(defvar epc:demo-dir (expand-file-name "demo" epc:source-dir))


(defmacro epc:with-self-server-client (connect-function &rest body)
  `(lexical-let*
       ((server-process (epcs:server-start ,connect-function t))
        (client-mngr (epc:start-epc-debug
                      (process-contact
                       server-process :service)))
        (dfinish (lambda (x)
                   (epc:stop-epc client-mngr)
                   (epcs:server-stop server-process))))
     ,@body
     ))

(ert-deftest epc:test-echo ()
  (epc:with-self-server-client
   (lambda (mngr)
     (epc:define-method mngr 'echo (lambda (x) x)))
   (deferred:$
     (epc:call-deferred client-mngr 'echo '("echo test"))
     (deferred:nextc it
       (lambda (x)
         (should (equal "echo test" x))))
     (deferred:watch it dfinish)
     (deferred:sync! it))))

(ert-deftest epc:test-echo-list ()
  (epc:with-self-server-client
   (lambda (mngr)
     (epc:define-method mngr 'echo (lambda (x) x)))
   (deferred:$
     (epc:call-deferred client-mngr 'echo '((1 2 "echo test")))
     (deferred:nextc it
       (lambda (x)
         (should (equal '(1 2 "echo test") x))))
     (deferred:watch it dfinish)
     (deferred:sync! it))))

(ert-deftest epc:test-add ()
  (epc:with-self-server-client
   (lambda (mngr)
     (epc:define-method mngr 'add '+))
   (deferred:$
     (epc:call-deferred client-mngr 'add '(1 2 3))
     (deferred:nextc it
       (lambda (x)
         (should (equal 6 x))))
     (deferred:watch it dfinish)
     (deferred:sync! it))))

(ert-deftest epc:test-deferred ()
  (epc:with-self-server-client
   (lambda (mngr)
     (epc:define-method
      mngr 'deferred
      (lambda (x) (deferred:next (lambda () "OK")))))
   (deferred:$
     (epc:call-deferred client-mngr 'deferred '("OK?"))
     (deferred:nextc it
       (lambda (x)
         (should (equal "OK" x))))
     (deferred:watch it dfinish)
     (deferred:sync! it))))

(ert-deftest epc:test-large-data ()
  (ert-skip "Failed now, we should solve it later.")
  (lexical-let ((len (* 65536 2)))
    (epc:with-self-server-client
     (lambda (mngr) (epc:define-method mngr 'large-echo (lambda (x) x)))
     (deferred:$
       (epc:call-deferred client-mngr 'large-echo (make-string len ?x))
       (deferred:nextc it
         (lambda (x)
           (should (= len (length x)))))
       (deferred:watch it dfinish)
       (deferred:sync! it)))))

(ert-deftest epc:test-multibytes ()
  (lexical-let ((str "日本語能力!!ソﾊﾝｶｸ"))
    (epc:with-self-server-client
     (lambda (mngr)
       (epc:define-method
        mngr 'echo
        (lambda (x) (cond ((equal x str) str)
                          (t (error "Different content!"))))))
     (deferred:$
       (epc:call-deferred client-mngr 'echo (list str))
       (deferred:nextc it
         (lambda (x)
           (should (equal x str))))
       (deferred:watch it dfinish)
       (deferred:sync! it)))))

(ert-deftest epc:test-ping-pong ()
  (epc:with-self-server-client
   (lambda (mngr)
     (lexical-let ((mngr mngr))
       (epc:define-method
        mngr 'ping (lambda (x)
                     (epc:call-deferred mngr 'pong (list (1+ x)))))))
   (epc:define-method
    client-mngr 'pong
    (lambda (x)
      (cond
       ((< 3 x) x)
       (t (epc:call-deferred
           client-mngr 'ping (list (1+ x)))))))
   (deferred:$
     (epc:call-deferred client-mngr 'ping (list 1))
     (deferred:nextc it
       (lambda (x)
         (should (equal 4 x))))
     (deferred:watch it dfinish)
     (deferred:sync! it))))

(ert-deftest epc:test-app-error ()
  (epc:with-self-server-client
   (lambda (mngr)
     (epc:define-method mngr 'error-calc (lambda (x) (/ 1 0))))
   (deferred:$
     (epc:call-deferred client-mngr 'error-calc (list 0))
     (deferred:nextc it (lambda (x) nil))
     (deferred:error it
       (lambda (x)
         (destructuring-bind (sym msg) x
         (should (and (eq sym 'error)
                      (string-match "arith-error" msg))))))
     (deferred:watch it dfinish)
     (deferred:sync! it))))

(ert-deftest epc:test-epc-error ()
  (epc:with-self-server-client
   (lambda (mngr) ) ; nothing
   (deferred:$
     (epc:call-deferred client-mngr 'some-method 0)
     (deferred:nextc it (lambda (x) nil))
     (deferred:error it
       (lambda (x)
         (destructuring-bind (sym msg) x
           (should (and (eq sym 'epc-error)
                        (string-match "^EPC-ERROR:" msg))))))
     (deferred:watch it dfinish)
     (deferred:sync! it))))

(ert-deftest epc:test-epc-methods ()
  (epc:with-self-server-client
   (lambda (mngr)
     (epc:define-method
      mngr 'echo (lambda (xs) xs) "XS" "Return XS")
     (epc:define-method
      mngr 'add (lambda (xs) (apply '+ xs)) "XS.." "Sum XS"))
   (deferred:$
     (epc:query-methods-deferred client-mngr)
     (deferred:nextc it
       (lambda (x)
         (should (equal x '((add "XS.." "Sum XS")
                            (echo "XS" "Return XS"))))))
     (deferred:watch it dfinish)
     (deferred:sync! it))))

(ert-deftest epc:test-epc-server-counts ()
  (lexical-let (server-count1 server-count2
                client-count1 client-count2)
    (epc:with-self-server-client
     (lambda (mngr) (epc:define-method mngr 'echo (lambda (x) x)))
     (deferred:$
       (epc:call-deferred client-mngr 'echo (list 0))
       (deferred:nextc it
         (deferred:lambda (x)
           (cond
            ;; * test 1
            ;; waiting for finishing other threads
            ((< 1 (length epcs:server-processes))
             (deferred:nextc (deferred:wait 30) self))
            (t nil))))
       (deferred:nextc it
         (lambda (x)
           (setq server-count1 (length epcs:server-processes)
                 client-count1 (length epcs:client-processes))))
       (deferred:watch it dfinish)
       (deferred:nextc it
         (lambda (x)
           (setq server-count2 (length epcs:server-processes)
                 client-count2 (length epcs:client-processes))
           ;; * test 2
           ;; comparing connection numbers
           (should (and (= 0 server-count2) (= 1 server-count1)
                        (= 0 client-count2) (= 1 client-count1)))))
       (deferred:sync! it)))))

(defun epc:test-start-echo-server ()
  (let ((emacs (concat invocation-directory invocation-name))
        (process-environment (mapcar #'identity process-environment)))
    ;; See: (info "(emacs) General Variables")
    (setenv "EMACSLOADPATH"
            (mapconcat #'identity
                       (loop for p in load-path
                             for e = (expand-file-name p)
                             ;; `file-directory-p' is required to suppress
                             ;; Warning: Lisp directory `...' does not exist.
                             when (file-directory-p e)
                             collect e)
                       path-separator))
    (epc:start-epc-deferred
     emacs
     `("-Q" "--batch"
       "-l" ,(expand-file-name "echo-server.el" epc:demo-dir)))))

(defun epc:test-start-epc-deferred-success ()
  (deferred:nextc (epc:test-start-echo-server)
    (lambda (mngr)
      (epc:stop-epc mngr)
      t)))

(defun epc:test-start-epc-deferred-fail ()
  (deferred:$
    (epc:start-epc-deferred "false" nil)
    (deferred:nextc it (lambda (_) nil))
    (deferred:error it (lambda (_) t))))


;;==================================================
;; Async Test Framework (based on deferred.el)

;; * template
;;
;; (defun cc:test-template ()
;;   (lexical-let*
;;       ((dtest (deferred:new)) (x nil))
;;
;;     (deferred:callback dtest
;;       (if x t (format "Fail %s" x)))
;;
;;     dtest))
;; (cc:debug (cc:test-fib-gen) "Fib10 : %s" x)

(defvar cc:test-functions
  '(
    epc:test-echo
    epc:test-echo-list
    epc:test-add
    epc:test-deferred
    epc:test-ping-pong
    epc:test-epc-error
    epc:test-app-error
    ;;epc:test-large-data
    epc:test-multibytes
    epc:test-epc-server-counts
    epc:test-epc-methods
    epc:test-start-epc-deferred-success
    epc:test-start-epc-deferred-fail
    ))


(defmacro cc:debug (d msg &rest args)
  `(deferred:nextc ,d
     (lambda (x) (funcall 'message ,msg ,@args) x)))

(defvar cc:test-finished-flag nil)

(defun cc:test-all (&optional on-fail-function)
  (interactive)
  (lexical-let ((start-time (float-time)))
    (deferred:$
      (deferred:parallel
        (loop for i in cc:test-functions
              collect (cons i (deferred:timeout 3000 "timeout" (funcall i)))))
      (deferred:nextc it
        (lambda (results)
          (pop-to-buffer
           (with-current-buffer (get-buffer-create "*cc:test*")
             (erase-buffer)
             (loop for i in results
                   for name = (car i)
                   for result = (cdr i)
                   with fails = 0
                   do (insert (format "%s : %s\n" name
                                      (if (eq t result) "OK"
                                        (format "FAIL > %s" result))))
                   (unless (eq t result) (incf fails))
                   finally
                   (goto-char (point-min))
                   (insert (format "Test Finished : %3f sec (%s)\nTests Fails: %s / %s\n"
                                   (- (float-time) start-time)
                                   (format-time-string "%Y/%m/%d %H:%M:%S" (current-time))
                                   fails (length results)))
                   (when (and (< 0 fails) (get-buffer epc:debug-buffer))
                     (insert "==================\n"
                             (with-current-buffer (get-buffer epc:debug-buffer)
                               (buffer-string))
                             "==================\n")))
             (message (buffer-string))
             (current-buffer)))
          (setq cc:test-finished-flag t))))

    (while (null cc:test-finished-flag)
      (sleep-for 0 10) (sit-for 0 10))))


;; (progn (eval-current-buffer) (cc:test-all))

(provide 'test-epc)
;;; test-epc.el ends here
