package Cpanel::Pkgr::Apt;

# cpanel - Cpanel/Pkgr/Apt.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Pkgr::Apt

=head1 DESCRIPTION

Interface to common dpkg commands.

WARNING: Prefer using Cpanel::Pkgr instead of calling Cpanel::Pkgr::Apt directly

=head1 SYNOPSIS

    my $dpkg = Cpanel::Pkgr::Apt->new;
    $dpkg->what_owns('file1')
    ...

=cut

use cPstrict;

use parent 'Cpanel::Pkgr::Base';

use Cpanel::Slurper                     ();
use Cpanel::Binaries::Debian::Dpkg      ();
use Cpanel::Binaries::Debian::DpkgQuery ();
use Cpanel::Binaries::Debian::AptCache  ();
use Cpanel::Binaries::Gpg               ();

sub name ($self) { return 'apt' }

sub binary_dpkg ($self) {

    return $self->{_dpkg} //= Cpanel::Binaries::Debian::Dpkg->new();
}

sub binary_dpkg_query ($self) {

    return $self->{_dpkg_query} //= Cpanel::Binaries::Debian::DpkgQuery->new();
}

sub binary_apt_cache ($self) {

    return $self->{_apt_cache} //= Cpanel::Binaries::Debian::AptCache->new();
}

sub is_installed ( $self, $pkg ) {
    my $r = $self->binary_dpkg_query->cmd( qw{--show --showformat}, q[${db:Status-Abbrev}\n], $pkg ) // {};
    return 0 unless defined $r->{status} && $r->{status} == 0;

    my $out = $r->{output} // '';
    return index( $out, 'ii' ) == 0 ? 1 : 0;
}

=head2 what_owns ($self, $file)

=cut

sub what_owns ( $self, @files ) {

    my $pkg_version = {};

    foreach my $file (@files) {
        my $pkg = $self->binary_dpkg->what_owns($file)
          or die("Cannot find the package which owns the file: $file");

        $pkg_version->{$pkg} //= $self->get_package_version($pkg) // 0;
    }

    return $pkg_version;
}

sub what_owns_no_errors ( $self, @files ) {
    my $packages = $self->binary_dpkg->what_owns_files_no_errors(@files);

    return unless ref $packages;

    my $pkg_version = {};

    # ideally we would like to get all in one request above
    foreach my $pkg ( $packages->@* ) {
        $pkg_version->{$pkg} //= $self->get_package_version($pkg) // 0;
    }

    return $pkg_version;
}

sub get_package_requires ( $self, $pkg ) {

    my $r = $self->binary_apt_cache->cmd( qw{show}, $pkg ) // {};

    return unless defined $r->{status} && $r->{status} == 0;

    my ($depends_line) = grep { m/^Depends:/ } split( "\n", $r->{output} // '' );
    length $depends_line or return {};

    $depends_line =~ s/^Depends:\s+//;

    my %deps;

    foreach my $package ( split( ', ', $depends_line ) ) {
        my $version = 0;

        next if $package =~ m{^<};    # skipping virtual package for now

        if ( index( $package, " " ) > 0 ) {
            ( $package, $version ) = split( " ", $package, 2 );
            $version =~ s{^\(\s*}{};
            $version =~ s{\s*\)$}{};
        }

        next if $package eq $pkg;     # Skip if it's depending on itself.

        $deps{$package} = $version;
    }

    return \%deps;
}

# reverse dependencies
# ╰─> apt-cache rdepends --no-recommends --no-suggests --no-enhances --recurse cpanel-perl-532
sub get_packages_dependencies ( $self, @filter ) {

    # dpkg-query --show --showformat '${binary:Package} ${Depends}\n' 'ubuntu-*'
    my $r = $self->binary_dpkg_query->cmd(
        qw{--show --showformat},
        q[${Depends}\n],    # maybe add the ${binary:Package} name
        @filter
    ) // {};

    return {} unless defined $r->{status} && $r->{status} == 0;

    # note deps are flat when using multiple filters,
    #   preserving consistency with Pkgr::Yum
    my $deps = {};

    my @lines = split( "\n", $r->{output} // '' );

    foreach my $line (@lines) {

        my @deps = split( /\s*,\s*/, $line );

        foreach my $d (@deps) {
            if ( $d =~ s{^ (.+) \s+ \( ( [^)]+ ) \) }{}x ) {    # when having a rule
                my ( $name, $rule ) = ( $1, $2 );
                $deps->{$name} = $rule;
            }
            else {
                $deps->{$d} = undef;                            # common case
            }
        }
    }

    return $deps;
}

sub list_files_from_package_path ( $self, $package_path ) {

    my $r = $self->binary_dpkg->cmd(
        qw{-c},
        $package_path
    ) // {};

    return () unless defined $r->{status} && $r->{status} == 0;

    my @lines = split( "\n", $r->{output} // '' );

    my @files;

    foreach my $l (@lines) {
        my ( $perms, $owner, $size, $date, $time, $file ) = split( /\s+/, $l, 6 );
        next unless defined $file;
        $file =~ s{^\.}{};
        next if $file =~ m{/$};    # not a file but a directory
        push @files, $file if length $file;
    }

    return @files;
}

sub list_files_from_installed_package ( $self, $package ) {

    my $r = $self->binary_dpkg->cmd(
        qw{-L},
        $package
    ) // {};

    return () unless defined $r->{status} && $r->{status} == 0;

    my @files = split( "\n", $r->{output} // '' );

    return @files;
}

=head2 installed_packages ($self)

returns a hash of all packages installed on the local system.

=cut

sub installed_packages ( $self, @filter ) {

    my $r = $self->binary_dpkg_query->cmd(
        qw{--show --showformat},
        q[${db:Status-Abbrev} ${Package} ${Version} ${Architecture}\n],
        @filter
    ) // {};

    # NOTE, this returns 256 if any package is not found! That said,
    # we can still get useful output if only some are found!
    return {} unless defined $r->{status};

    my $installed = {};

    my @lines = split( "\n", $r->{output} // '' );

    foreach my $line (@lines) {
        next unless index( $line, 'ii' ) == 0;

        my ( $state, $package, $version, $arch ) = split( /\s+/, $line );

        $installed->{$package} = $version;

        if ( $self->{with_arch_suffix} ) {
            $installed->{$package} .= '.' . $arch;
        }
    }

    return $installed;
}

sub get_version_for_packages ( $self, @list ) {

    return $self->installed_packages(@list);
}

sub get_version_with_arch_suffix ( $self, @list ) {

    local $self->{'with_arch_suffix'} = 1;

    return $self->get_version_for_packages(@list);
}

sub what_provides ( $self, $pkg_or_file ) {
    state %provides_cache;    # WARNING: This cache is never cleared during the life of the process.
    state $parsed = 0;

    # Use cache if present.
    return $provides_cache{$pkg_or_file} if exists $provides_cache{$pkg_or_file};

    #    $self->binary_dpkg_query

    if ( $pkg_or_file =~ qr{/} ) {
        my $r = $self->binary_dpkg->cmd( qw{-S}, $pkg_or_file ) // {};

        return unless defined $r->{status} && $r->{status} == 0;

        my ($first_line) = split( "\n", $r->{output} // '' );

        return unless defined $first_line;

        my ( $pkg, undef ) = split( ':', $first_line );
        return $pkg;
    }

    return $pkg_or_file if $self->is_installed($pkg_or_file);

    # It's not a file we're asking about and we've already parsed the status file.
    return if $parsed;

    my $r = $self->binary_dpkg_query->cmd('--status') // {};
    return unless defined $r->{status} && $r->{status} == 0;

    my $current_package;
    foreach my $line ( split( "\n", $r->{output} // '' ) ) {
        if ( $line =~ m/^Package:\s+([\.\-\+a-z0-9]+)/ ) {
            $current_package = $1;
            next;
        }

        # Provides: libansicolor-perl (= 4.06), libarchive-tar-perl (= 2.32), libattribute-handlers-perl (= 1.01), libautodie-perl (= 2.29-2), libcompress-raw-bzip2-perl (= 2.084), ...
        if ( $line =~ m/^Provides:\s+(\S.+)/ ) {
            my @provides = split( ", ", "$1" );
            foreach my $provide (@provides) {
                if ( $provide =~ m/^([\.\-\+a-z0-9]+)\b/ ) {    #
                    $provides_cache{$1} = $current_package;
                }
            }
        }
    }
    $parsed = 1;

    return $provides_cache{$pkg_or_file} if exists $provides_cache{$pkg_or_file};

    return;
}

=head2 is_capability_available( $search )

Check if a capability (package, virtual package, file...) is available.
Returns a boolean: 1/0.

=cut

sub is_capability_available ( $self, $search ) {
    return 0 unless defined $search;
    return $self->what_provides($search) ? 1 : 0;
}

=head2 what_provides_with_details($file)

Gets all installed packages providing $file locally.
Returns ARRAYREF of package description HASHREFs.

=cut

sub what_provides_with_details ( $self, $pkg_or_file ) {
    my $str = $self->binary_dpkg->whatprovides($pkg_or_file) // '';
    return [ map { $self->binary_apt_cache->show($_) } split( ", ", $str ) ];
}

sub query ( $self, @filter ) {

    return $self->binary_dpkg_query->query(@filter);
}

=head2 get_package_scripts( @pkgs )

=cut

sub get_package_scripts ( $self, @pkgs ) {
    my $pkg_info_dir = '/var/lib/dpkg/info';

    my @info_files = Cpanel::Slurper::read_dir($pkg_info_dir);

    my @script_files;
    foreach my $file ( sort @info_files ) {
        next if $file =~ m/\.(?:md5sums|list|conffiles|shlibs|triggers)$/;
        next unless grep { $file =~ m/^\Q$_\E\.[a-z]+$/ } @pkgs;

        push @script_files, $file;
    }

    my %scripts;
    foreach my $file (@script_files) {
        my ( $package, $script_type ) = $file =~ m/(^.+)\.([a-z]+)$/;
        length $script_type or next;    # Something went wrong if we hit this.

        my $content = eval { Cpanel::Slurper::read("$pkg_info_dir/$file") };
        next unless length $content && $content =~ m/\S/;    # Empty file.

        $scripts{$package} //= '';
        $scripts{$package} .= "$script_type scriptlet:\n\n$content\n";
    }

    return \%scripts;
}

=head2 verify_package_manager_can_install_packages( $logger = undef )

=cut

sub verify_package_manager_can_install_packages ( $self, $logger = undef ) {

    # right now we do not know how to detect a broken apt database
    #   initial idea: using 'apt-get check'

    return ( 1, '' );
}

=head2 remove_packages_nodeps( @packages )

Remove packages from the system using dpkg. Return output of command.

=cut

sub remove_packages_nodeps ( $self, @packages ) {
    return '' unless @packages;    # Nothing to do!
    my $r = $self->binary_dpkg->cmd(
        '--ignore-depends=' . join( ',', @packages ),
        '-r',
        @packages
    );
    return $r->{'output'} // '';
}

=head2 lock_for_external_install ( $logger )

retrieve a cPanel lock for using the apt system.

=cut

sub lock_for_external_install ( $self, $logger ) {
    return $self->binary_dpkg->get_lock_for_cmd( $logger, [ '-i', 'and install external system packages.' ] );    # dpkg -i needs a lock. we'll use this to make sure the system gives a lock.
}

###
### Note: these methods are not yet implemented, crash on call for now
###

sub installed_cpanel_obsoletes ($self) {
    die "installed_cpanel_obsoletes is not implemented for package " . __PACKAGE__ . "\n";
}

sub add_repo_keys ( $self, @keys2import ) {

    die "add_repo_keys is not implemented for package " . __PACKAGE__ . "\n";
}

sub install_or_upgrade_from_file ( $self, @pkg_paths ) {
    $self->binary_dpkg->run_or_die( '--skip-same-version', '--install', @pkg_paths );
    return;
}

=head2 verify_package ( $package, $file=undef )

Verifies a package's integrity.

If you pass a file as a second argument, only the one file in that package will be validated.

Returns 1 if the package validates, 0 otherwise.

=cut

sub verify_package ( $self, $package, $file = undef ) {

    # use `dpkg -V $package`

    my $r = $self->binary_dpkg->cmd(
        '-V',
        $package
    );

    my $out = $r->{'output'} // '';

    if ( $r->{status} ) {
        return 1 if $out =~ qr{not installed}i;
        return 0;
    }

    if ( length $file ) {

        # Just show the one file as being altered.
        $out = join "\n", grep { m{ \Q$file\E$} } split( "\n", $out );
    }

    return length $out ? 0 : 1;
}

sub package_file_is_signed_by_cpanel ( $self, $file ) {

    return unless defined $file && $file =~ qr{\.deb$} && -e $file;

    my $gpg = Cpanel::Binaries::Gpg->new();
    return $gpg->is_file_signed_by_cpanel($file);
}

1;
