(in-package :lem)

(export '(*pre-command-hook*
          *post-command-hook*
          *exit-editor-hook*
          interactive-p
          continue-flag
          pop-up-backtrace))

(defvar *pre-command-hook* '())
(defvar *post-command-hook* '())
(defvar *exit-editor-hook* '())

(defvar +exit-tag+ (gensym "EXIT"))
(defvar +bailout-tag+ (make-symbol "BAILOUT"))

(defmacro with-catch-bailout (&body body)
  `(catch +bailout-tag+
     ,@body))

(defun bailout (condition)
  (throw +bailout-tag+
    (with-output-to-string (stream)
      (princ condition stream)
      (uiop/image:print-backtrace
       :stream stream
       :condition condition))))

(defun pop-up-backtrace (condition)
  (let ((buffer (get-buffer-create "*EDITOR ERROR*")))
    (erase-buffer buffer)
    (display-buffer buffer)
    (with-open-stream (stream (make-buffer-output-stream (buffer-point buffer)))
      (princ condition stream)
      (fresh-line stream)
      (uiop/image:print-backtrace
       :stream stream
       :count 100))))

(defmacro with-error-handler (() &body body)
  `(handler-case-bind ((lambda (condition)
                         (handler-bind ((error #'bailout))
                           (pop-up-backtrace condition)))
                       ,@body)
                      ((condition) (declare (ignore condition)))))

(defvar *interactive-p* nil)
(defun interactive-p () *interactive-p*)

(defvar *last-flags* nil)
(defvar *curr-flags* nil)

(defun continue-flag (flag)
  (prog1 (cdr (assoc flag *last-flags*))
    (push (cons flag t) *last-flags*)
    (push (cons flag t) *curr-flags*)))

(defun call-command (cmd arg)
  (run-hooks *pre-command-hook*)
  (prog1 (funcall cmd arg)
    (buffer-undo-boundary)
    (run-hooks *post-command-hook*)))

(defun %do-command-loop (function)
  (loop :for *last-flags* := nil :then *curr-flags*
        :for *curr-flags* := nil
        :do (let ((*interactive-p* t))
              (funcall function))))

(defmacro do-command-loop ((&key toplevel) &body body)
  `(if ,toplevel
       (catch +exit-tag+
         (%do-command-loop
          (lambda ()
            (with-error-handler ()
              ,@body))))
       (%do-command-loop (lambda () ,@body))))

(defun command-loop (toplevel)
  (do-command-loop (:toplevel toplevel)
    (when (= 0 (event-queue-length)) (redraw-display))
    (handler-case
        (handler-bind ((editor-condition
                        (lambda (c)
                          (declare (ignore c))
                          (stop-record-key))))
          (let ((cmd (progn
                       (start-idle-timers)
                       (prog1 (read-key-command)
                         (stop-idle-timers)))))
            (unless (minibuffer-window-active-p) (message nil))
            (call-command cmd nil)))
      (editor-condition (c)
                        (message "~A" c)))))

(defun exit-editor (&optional report)
  (run-hooks *exit-editor-hook*)
  (throw +exit-tag+ report))