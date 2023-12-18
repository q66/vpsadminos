;; Load vpsAdminOS-specific configuration from /etc/config/vpsadminos.scm
(add-to-load-path "/etc/config")
(use-modules (vpsadminos))

;; System configuration
(use-modules (gnu) (gnu system locale))
(use-service-modules admin networking shepherd ssh sysctl)
(use-package-modules certs ssh bash package-management vim)

(operating-system
  (host-name "guix")
  ;; Servers usually use UTC regardless of the location.
  (timezone "Etc/UTC")
  (locale "en_US.utf8")
  (firmware '())
  (initrd-modules '())
  (kernel %ct-dummy-kernel)
  (packages (cons* vim
                   %ct-packages))

  (essential-services (modify-services
                          (operating-system-default-essential-services this-operating-system)
                        (delete firmware-service-type)
                        (delete (service-kind %linux-bare-metal-service))))

  (bootloader %ct-bootloader)

  (file-systems %ct-file-systems)

  (services (cons* (service openssh-service-type
                            (openssh-configuration
                             (openssh openssh-sans-x)
                             (permit-root-login #t)
                             (password-authentication? #t)))
                   %ct-services)))
