;; Configuration specific for containers on vpsAdminOS
;;
;; If you're experiencing issues, try updating this file to the latest version
;; from vpsAdminOS repository:
;;
;;  https://github.com/vpsfreecz/vpsadminos/blob/staging/image-scripts/images/guix/vpsadminos.scm
;;
(define-module (vpsadminos)
  #:use-module (gnu)
  #:use-module (gnu packages)
  #:use-module (gnu packages bash)
  #:use-module (gnu services networking)
  #:use-module (gnu services shepherd)
  #:use-module (guix build-system trivial)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (srfi srfi-1)
  #:export (%ct-bootloader
            %ct-dummy-kernel
            %ct-file-systems
            %ct-services))

;;; The bootloader is not required.  This is running inside a container, and the
;;; start menu is populated by parsing /var/guix/profiles.  However bootloader
;;; is a mandatory field, and the typical grub-bootloader requires users to
;;; always pass the --no-bootloader flag.  By providing this bootloader
;;; configuration (it does not do anything, but installs fine), we remove the
;;; need to remember to pass the flag.  At the cost of ~8MB in /boot.
(define %ct-bootloader
  (bootloader-configuration
   (bootloader grub-efi-netboot-removable-bootloader)
   (targets '("/boot"))))

;;; It seems any package can be passed as an kernel, so create empty one for
;;; that purpose.
(define %ct-dummy-kernel
  (package
    (name "dummy-kernel")
    (version "1")
    (source #f)
    (build-system trivial-build-system)
    (arguments
     (list
      #:builder #~(mkdir #$output)))
    (synopsis "Dummy kernel")
    (description
     "In container environment, the kernel is provided by the host.  However we
still need to specify a kernel in the operating-system definition, hence this
package.")
    (home-page #f)
    (license #f)))

(define %ct-file-systems
  (cons* (file-system                   ; Dummy rootfs
           (device "/dev/null")
           (mount-point "/")
           (type "dummy"))
         ;; Used by vpsadminos scripting.  Can go away once /run as a whole is
         ;; on tmpfs.
         (file-system
           (device "none")
           (mount-point "/run/vpsadminos")
           (type "tmpfs")
           (check? #f)
           (flags '(no-suid no-dev no-exec))
           (options "mode=0755")
           (create-mount-point? #t))
         (map (λ (fs)
                (cond
                 ;; %immutable-store is usually mounted with no-atime.  That
                 ;; does not work in the vpsFree (causing the boot to hang), so
                 ;; we need to delete the flag.
                 ((eq? fs %immutable-store)
                  (file-system
                    (inherit fs)
                    (flags (delete 'no-atime (file-system-flags fs)))))
                 (else
                  fs)))
              (fold delete
                    %base-file-systems
                    (list
                     ;; Already mounted by vpsadminos
                     %pseudo-terminal-file-system
                     ;; Cannot be mounted due to the permissions
                     %debug-file-system
                     %efivars-file-system)))))

;; Service which runs network configuration script generated by osctld
;; from vpsAdminOS
(define vpsadminos-networking
  (shepherd-service
   (requirement '(file-system-/run/vpsadminos))
   (provision '(vpsadminos-networking loopback))
   (documentation "Setup network on vpsAdminOS")
   (one-shot? #t)
   (start #~(lambda _ (invoke #$(file-append bash "/bin/bash")
                              "-c" "
[ -f  /run/vpsadminos/network ] && exit 0
touch /run/vpsadminos/network
\"$SHELL\" /ifcfg.add
")))))

;; Modified %base-services from
;;
;;  https://git.savannah.gnu.org/cgit/guix.git/tree/gnu/services/base.scm
;;
;; We start mingetty only on /dev/console and add our own service to handle
;; networking.
(define %ct-services
  (cons* (service mingetty-service-type
                  (mingetty-configuration
                   (tty "console")))
         (simple-service 'vpsadminos-networking
                         shepherd-root-service-type (list vpsadminos-networking))
         ;; dhcp provisions 'networking and it is useful for development setup.
         ;; Maybe in the future we could handle it by 'vpsadminos-networking
         ;; and to run dhcp only when there is an actual interface.
         (service dhcp-client-service-type)

         (modify-services %base-services
           (delete console-font-service-type)
           (delete agetty-service-type)
           (delete mingetty-service-type)
           (delete urandom-seed-service-type)
           ;; loopback is configured by vpsadminos-networking
           (delete static-networking-service-type)
           ;; We need no rules.
           (udev-service-type config =>
                              (udev-configuration
                               (inherit config)
                               (rules '()))))))
