pkgname=btrbackup
pkgver=0.2
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
        "btrbackupconfig.tcl")
md5sums=('SKIP'
         'SKIP')

#build() {
#  true
#}

package() {
  cd "${srcdir}/"
  install -Dm744 btrbackup.tcl "$pkgdir/usr/bin/btrbackup"
  install -Dm644 btrbackupconfig.tcl "$pkgdir/etc/btrbackupconfig.tcl"
}

# vim:set ts=2 sw=2 et:
