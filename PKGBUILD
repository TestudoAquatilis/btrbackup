pkgname=btrbackup
pkgver=0.5
pkgrel=1
pkgdesc="A tcl script for backups from one btrfs filesystem to another using snapshots"
url="https://github.com/TestudoAquatilis/btrbackup"
arch=('any')
license=('GPLv3')
depends=('tcl' 'btrfs-progs' 'rsync')
optdepends=()
makedepends=()
conflicts=()
replaces=()
backup=('etc/btrbackupconfig.tcl')
#install='foo.install'
source=("btrbackup.tcl"
        "btrbackupconfig.tcl"
        "logrotate")
md5sums=('a2878d9c8f365123c46bc45c2160bc08'
         '4154c485744e89d1d9c33be3f236c781'
         '4b7917c29f4945e1e3eb79bb31f3f4cd')

package() {
  cd "${srcdir}/"
  install -Dm744 btrbackup.tcl "$pkgdir/usr/bin/btrbackup"
  install -Dm644 btrbackupconfig.tcl "$pkgdir/etc/btrbackupconfig.tcl"
  install -Dm644 logrotate "$pkgdir/etc/logrotate.d/btrbackup"
}

# vim:set ts=2 sw=2 et:
