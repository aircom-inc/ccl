;;;-*-Mode: LISP; Package: GUI -*-
;;;
;;;   Copyright (C) 2007 Clozure Associates

(in-package "GUI")

(defclass lisp-application-delegate (ns:ns-object)
    ()
  (:metaclass ns:+ns-object))

;;; This method is a good place to:
;;;  * register value transformer names
;;;  * register default user defaults
(objc:defmethod (#/initialize :void) ((self +lisp-application-delegate))
  (#/setValueTransformer:forName: ns:ns-value-transformer
				  (make-instance 'font-to-name-transformer)
				  #@"FontToName")

  (let* ((domain (#/standardUserDefaults ns:ns-user-defaults))
	 (initial-values (cocoa-defaults-initial-values))
	 (dict (#/mutableCopy initial-values)))
    (declare (special *standalone-cocoa-ide*))
    (#/registerDefaults: domain dict)
    (#/release dict)
    (update-cocoa-defaults)
    (when *standalone-cocoa-ide*
      (init-ccl-directory-for-ide))))

(defun init-ccl-directory-for-ide ()
  (let* ((bundle-path (#/bundlePath (#/mainBundle ns:ns-bundle)))
         (parent (#/stringByDeletingLastPathComponent bundle-path))
         (path (ccl::ensure-directory-pathname
                (lisp-string-from-nsstring parent))))
    (ccl::replace-base-translation "ccl:" path)))
         

(objc:defmethod (#/applicationWillFinishLaunching: :void)
    ((self lisp-application-delegate) notification)
  (declare (ignore notification))
  (initialize-user-interface)
  (let* ((c (#/init (#/alloc console-window))))
    (unless (%null-ptr-p c)
      (setf (console *nsapp*) c))))

(objc:defmethod (#/applicationWillTerminate: :void)
		((self lisp-application-delegate) notification)
  (declare (ignore notification))
  ;; UI has decided to quit; terminate other lisp threads.
  (ccl::prepare-to-quit))

(defloadvar *preferences-window-controller* nil)

(objc:defmethod (#/showPreferences: :void) ((self lisp-application-delegate)
					    sender)
  (declare (ignore sender))
  (when (null *preferences-window-controller*)
    (setf *preferences-window-controller*
	  (make-instance 'preferences-window-controller)))
  (#/showWindow: *preferences-window-controller* self))

(defloadvar *processes-window-controller* nil)

(objc:defmethod (#/showProcessesWindow: :void) ((self lisp-application-delegate)
						sender)
  (declare (ignore sender))
  (when (null *processes-window-controller*)
    (setf *processes-window-controller*
	  (make-instance 'processes-window-controller)))
  (#/showWindow: *processes-window-controller* self))

(defloadvar *apropos-window-controller* nil)

(objc:defmethod (#/showAproposWindow: :void) ((self lisp-application-delegate)
						sender)
  (declare (ignore sender))
  (when (null *apropos-window-controller*)
    (setf *apropos-window-controller*
	  (make-instance 'apropos-window-controller)))
  (#/showWindow: *apropos-window-controller* self))

(objc:defmethod (#/showSearchFiles: :void) ((self lisp-application-delegate)
                                            sender)
  ;;If command key is pressed, always make a new window
  ;;otherwise bring frontmost search files window to the front
  (declare (ignore sender))
  (let ((w nil))
    (if (or (current-event-command-key-p)
            (null (setf w (first-window-with-controller-type 'search-files-window-controller))))
      (let* ((wc (make-instance 'search-files-window-controller)))
        (setf w (#/window wc))
        (#/setWindowController: w wc))
      (#/makeKeyAndOrderFront: w self))))

(objc:defmethod (#/newListener: :void) ((self lisp-application-delegate)
                                        sender)
  (declare (ignore sender))
  (#/openUntitledDocumentOfType:display:
   (#/sharedDocumentController ns:ns-document-controller) #@"Listener" t))

(objc:defmethod (#/showListener: :void) ((self lisp-application-delegate)
                                        sender)
  (declare (ignore sender))
  (let* ((all-windows (#/orderedWindows *NSApp*))
	 (key-window (#/keyWindow *NSApp*))
	 (listener-windows ())
	 (top-listener nil))
    (dotimes (i (#/count all-windows))
      (let* ((w (#/objectAtIndex: all-windows i))
	     (wc (#/windowController w)))
	(when (eql (#/class wc) hemlock-listener-window-controller)
	  (push w listener-windows))))
    (setq listener-windows (nreverse listener-windows))
    (setq top-listener (car listener-windows))
    (cond 
     ((null listener-windows)
      (#/newListener: self +null-ptr+))
     ((eql key-window top-listener)
      ;; The current window is a listener.  If there is more than
      ;; one listener, bring the rear-most forward.
      (let* ((w (car (last listener-windows))))
	(if (eql top-listener w)
	  (#_NSBeep)
	  (#/makeKeyAndOrderFront: w +null-ptr+))))
     (t
      (#/makeKeyAndOrderFront: top-listener +null-ptr+)))))

(objc:defmethod (#/ensureListener: :void) ((self lisp-application-delegate)
					   sender)
  (declare (ignore sender))
  (let ((top-listener-document (#/topListener hemlock-listener-document)))
    (when (eql top-listener-document +null-ptr+)
      (let* ((dc (#/sharedDocumentController ns:ns-document-controller))
	     (wc nil))
	(setq top-listener-document
	      (#/makeUntitledDocumentOfType:error: dc #@"Listener" +null-ptr+))
	(#/addDocument: dc top-listener-document)
	(#/makeWindowControllers top-listener-document)
	(setq wc (#/lastObject (#/windowControllers top-listener-document)))
	(#/orderFront: (#/window wc) +null-ptr+)))))

(defvar *cocoa-application-finished-launching* (make-semaphore)
  "Semaphore that's signaled when the application's finished launching ...")

(objc:defmethod (#/applicationDidFinishLaunching: :void)
    ((self lisp-application-delegate) notification)
  (declare (ignore notification))
  (signal-semaphore *cocoa-application-finished-launching*))

(objc:defmethod (#/applicationOpenUntitledFile: :<BOOL>)
    ((self lisp-application-delegate) app)
  (when (zerop *cocoa-listener-count*)
    (#/newListener: self app)
    t))
