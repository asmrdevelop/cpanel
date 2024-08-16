package Cpanel::Binaries;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

# This module tracks the real location of all 3rd party binaries cPanel uses
# and provides a way to keep their symlinks updated in 3rdparty/bin

use strict;
use warnings;

#useful for testing
our @_OVERRIDES;
our $VERBOSE = 1;

use Cpanel::OS ();

# Define these constants first, as we use them to define other constants
use constant {
    PERL_MAJOR        => 536,
    PERL_LEGACY_MAJOR => 532,
    PHP_MAJOR         => 83,
    PHP_LEGACY_MAJOR  => 81,
    THIRD_PARTY       => q{/usr/local/cpanel/3rdparty},
};

use constant {
    THIRD_PARTY_BIN        => THIRD_PARTY . q{/bin},
    CPANEL_PERL            => THIRD_PARTY . q{/perl/} . PERL_MAJOR(),
    CPANEL_PERL_LEGACY     => THIRD_PARTY . q{/perl/} . PERL_LEGACY_MAJOR(),
    CPANEL_PHP             => THIRD_PARTY . q{/php/} . PHP_MAJOR(),
    CPANEL_PHP_LEGACY      => THIRD_PARTY . q{/php/} . PHP_LEGACY_MAJOR(),
    CPANEL_PHP_UNVERSIONED => THIRD_PARTY . q{/php/unversioned},
    SYSTEM_BIN             => q{/usr/bin},
    SYSTEM_SBIN            => q{/usr/sbin},
    LOCAL_BIN              => q{/usr/local/bin},
};

use constant {
    CPANEL_PERL_BIN       => CPANEL_PERL . q{/bin},
    CPANEL_PERL_SBIN      => CPANEL_PERL . q{/sbin},
    CPANEL_PHP_BIN        => CPANEL_PHP . q{/bin},
    CPANEL_PHP_LEGACY_BIN => CPANEL_PHP_LEGACY . q{/bin},
};

sub system_bin_locations {
    return {
        # ImageMagick binaries
        'identify' => SYSTEM_BIN,
        'convert'  => SYSTEM_BIN,
        'mogrify'  => SYSTEM_BIN,

        # firewalld binaries
        'firewall-cmd' => SYSTEM_BIN,
        'firewalld'    => SYSTEM_SBIN,

        # System bin binaries
        #   warning: check path location on CloudLinux 6 before adding a new entry
        'at'                 => SYSTEM_BIN,
        'atq'                => SYSTEM_BIN,
        'atrm'               => SYSTEM_BIN,
        'chattr'             => SYSTEM_BIN,
        'crontab'            => SYSTEM_BIN,
        'curl'               => SYSTEM_BIN,
        'dig'                => SYSTEM_BIN,
        'doveadm'            => SYSTEM_BIN,
        'dpkg-query'         => SYSTEM_BIN,
        'dsync'              => SYSTEM_BIN,
        'file'               => SYSTEM_BIN,
        'gcc'                => SYSTEM_BIN,
        'getfacl'            => SYSTEM_BIN,
        'gpg'                => SYSTEM_BIN,
        'gzip'               => SYSTEM_BIN,
        'host'               => SYSTEM_BIN,
        'iconv'              => SYSTEM_BIN,
        'ionice'             => SYSTEM_BIN,
        'iostat'             => SYSTEM_BIN,
        'ipcrm'              => SYSTEM_BIN,
        'ipcs'               => SYSTEM_BIN,
        'lsattr'             => SYSTEM_BIN,
        'lsof'               => SYSTEM_BIN,
        'mysql'              => SYSTEM_BIN,
        'mysql_config'       => SYSTEM_BIN,
        'mysql_upgrade'      => SYSTEM_BIN,
        'mysqladmin'         => SYSTEM_BIN,
        'mysqlcheck'         => SYSTEM_BIN,
        'mysqldump'          => SYSTEM_BIN,
        'nano'               => SYSTEM_BIN,
        'openssl'            => SYSTEM_BIN,
        'pdns_control'       => SYSTEM_BIN,
        'pdnsutil'           => SYSTEM_BIN,
        'perl'               => SYSTEM_BIN,
        'python2'            => THIRD_PARTY_BIN,
        'quota'              => SYSTEM_BIN,
        'repoquery'          => SYSTEM_BIN,
        'rsync'              => SYSTEM_BIN,
        'setfacl'            => SYSTEM_BIN,
        'ssh-keygen'         => SYSTEM_BIN,
        'ssh-keyscan'        => SYSTEM_BIN,
        'strace'             => SYSTEM_BIN,
        'sudo'               => SYSTEM_BIN,
        'systemctl'          => SYSTEM_BIN,
        'tail'               => SYSTEM_BIN,
        'test'               => SYSTEM_BIN,
        'unzip'              => SYSTEM_BIN,
        'vim'                => SYSTEM_BIN,
        'wall'               => SYSTEM_BIN,
        'xmlwf'              => SYSTEM_BIN,
        'yum'                => SYSTEM_BIN,
        'yum-config-manager' => SYSTEM_BIN,
        'zip'                => SYSTEM_BIN,

        # System sbin binaries
        'atd'            => SYSTEM_SBIN,
        'convertquota'   => SYSTEM_SBIN,
        'edquota'        => SYSTEM_SBIN,
        'exim'           => SYSTEM_SBIN,
        'exim_dbmbuild'  => SYSTEM_SBIN,
        'exim_tidydb'    => SYSTEM_SBIN,
        'grubby'         => SYSTEM_SBIN,
        'ifconfig'       => SYSTEM_SBIN,
        'ip'             => SYSTEM_SBIN,
        'ip6tables'      => SYSTEM_SBIN,
        'ip6tables-save' => SYSTEM_SBIN,
        'iptables'       => SYSTEM_SBIN,
        'iptables-save'  => SYSTEM_SBIN,
        'logrotate'      => SYSTEM_SBIN,
        'losetup'        => SYSTEM_SBIN,
        'mysqld'         => SYSTEM_SBIN,
        'named'          => SYSTEM_SBIN,
        'nft'            => SYSTEM_SBIN,
        'nscd'           => SYSTEM_SBIN,
        'pdns_server'    => SYSTEM_SBIN,
        'quotacheck'     => SYSTEM_SBIN,
        'quotaoff'       => SYSTEM_SBIN,
        'quotaon'        => SYSTEM_SBIN,
        'repquota'       => SYSTEM_SBIN,
        'rndc-confgen'   => SYSTEM_SBIN,
        'rsyslogd'       => SYSTEM_SBIN,
        'service'        => SYSTEM_SBIN,
        'sshd'           => SYSTEM_SBIN,

        # pkill (Currently used to terminate shell sessions)
        'pkill' => SYSTEM_BIN,

        # binaries that were in a specific location on previous major distros
        'bash'     => SYSTEM_BIN,
        'cat'      => SYSTEM_BIN,
        'cp'       => SYSTEM_BIN,
        'date'     => SYSTEM_BIN,
        'dd'       => SYSTEM_BIN,
        'df'       => SYSTEM_BIN,
        'echo'     => SYSTEM_BIN,
        'false'    => SYSTEM_BIN,
        'grep'     => SYSTEM_BIN,
        'hostname' => SYSTEM_BIN,
        'ls'       => SYSTEM_BIN,
        'mount'    => SYSTEM_BIN,
        'netstat'  => SYSTEM_BIN,
        'pwd'      => SYSTEM_BIN,
        'rm'       => SYSTEM_BIN,
        'rpm'      => SYSTEM_BIN,
        'sh'       => SYSTEM_BIN,
        'su'       => SYSTEM_BIN,
        'tar'      => SYSTEM_BIN,
        'true'     => SYSTEM_BIN,
        'umount'   => SYSTEM_BIN,
        'zcat'     => SYSTEM_BIN,

        # sbin version of those binaries
        'rsyslogd'   => SYSTEM_SBIN,
        'ip6tables'  => SYSTEM_SBIN,
        'ifconfig'   => SYSTEM_SBIN,
        'quotaoff'   => SYSTEM_SBIN,
        'losetup'    => SYSTEM_SBIN,
        'quotacheck' => SYSTEM_SBIN,
        'ip'         => SYSTEM_SBIN,
        'quotaon'    => SYSTEM_SBIN,
        'iptables'   => SYSTEM_SBIN,
        'service'    => SYSTEM_SBIN,
    };
}

sub dynamic_bin_location {
    my $binary = shift
      or die 'dynamic_bin_location($binary)';

    my %table = Cpanel::OS::binary_locations()->%*;
    return $table{$binary};
}

sub thirdparty_binary_locations {
    return {
        %{ _get_thirdparty_binary_locations_static() },
        %{ _get_thirdparty_binary_locations_dynamic() },
    };
}

# Map out what vars we gotta do a stat for.
our %dynamic_vars = (

    # Cpanel's php binaries.
    'pear'       => 1,
    'peardev'    => 1,
    'pecl'       => 1,
    'phar'       => 1,
    'php'        => 1,
    'php-cgi'    => 1,
    'php-config' => 1,
    'phpize'     => 1,
);

# Not all binaries exist on all server types.
our $cached_cleanup;    # Don't do these checks more than once.

sub _remove_server_type_specific_binaries {
    return if $cached_cleanup;
    return $cached_cleanup = 1;
}

sub _get_thirdparty_binary_location {
    my ($binary) = @_;

    _remove_server_type_specific_binaries();

    # Don't wanna autovivify here, as I'm using this to map later
    return ( exists( $dynamic_vars{$binary} ) ) ? _get_thirdparty_binary_locations_dynamic()->{$binary} : _get_thirdparty_binary_locations_static()->{$binary};
}

my $php_dir;

sub _get_thirdparty_binary_locations_dynamic {
    if ( !defined($php_dir) ) {
        $php_dir = Cpanel::Binaries::get_php_3rdparty_dir() . "bin";
    }

    _remove_server_type_specific_binaries();

    return { map { $_ => $php_dir } keys(%dynamic_vars) };
}

sub _get_thirdparty_binary_locations_static {
    return {
        # Spam Assassin
        'spamd'        => CPANEL_PERL_BIN,
        'spamc'        => CPANEL_PERL_BIN,
        'spamassassin' => CPANEL_PERL_BIN,
        'sa-compile'   => CPANEL_PERL_BIN,
        'sa-learn'     => CPANEL_PERL_BIN,
        'sa-update'    => CPANEL_PERL_BIN,

        # ClamAV
        'clamd'     => THIRD_PARTY_BIN,
        'clamdscan' => THIRD_PARTY_BIN,
        'freshclam' => THIRD_PARTY_BIN,

        # Misc 3rdparty
        'puttygen' => THIRD_PARTY_BIN,

        # Compression
        'pigz' => THIRD_PARTY_BIN,

        # SPF should not be listed here or it will overwrite cpanel-libspf2
        #'spfquery' => CPANEL_PERL_BIN,

        # re2c used by SA
        're2c' => THIRD_PARTY_BIN,

        # cPanel's perl
        'perl'       => CPANEL_PERL_BIN,
        'perlcc'     => CPANEL_PERL_BIN,
        'mysqldiff'  => CPANEL_PERL_BIN,
        'munin-cron' => CPANEL_PERL_BIN,

        # sbins
        'munin-node'           => CPANEL_PERL_SBIN,
        'munin-node-configure' => CPANEL_PERL_SBIN,

        #PostgreSQL client
        'psql'       => THIRD_PARTY_BIN,
        'pg_dump'    => THIRD_PARTY_BIN,
        'pg_restore' => THIRD_PARTY_BIN,

        # cPanel's python (currently a symlink to system python)
        'python' => THIRD_PARTY_BIN,

        # cPanel's Git.
        'git'                => THIRD_PARTY_BIN,
        'git-receive-pack'   => THIRD_PARTY_BIN,
        'git-shell'          => THIRD_PARTY_BIN,
        'git-upload-archive' => THIRD_PARTY_BIN,
        'git-upload-pack'    => THIRD_PARTY_BIN,

        # WordPress Toolkit
        'wp-toolkit' => LOCAL_BIN,

        # Imunify360
        'imunify360-agent' => SYSTEM_BIN,

        @_OVERRIDES,
    };
}

=pod

=head1 thirdparty_binary_names()

=head2 Description

This is to provide a method if we wish to name the symlink differently from the target.

=head2 Arguments

None

=head2 Returns

A hash reference where the key is the name of the symlink, and value is the name of
the target.

=cut

sub thirdparty_binary_names {
    return {};
}

sub LOG {
    my ($msg) = @_;
    return unless $VERBOSE && defined $msg;
    print "$msg\n";
    return;
}

sub optional_binaries {
    return qw/munin-cron munin-node munin-node-configure perlcc/;
}

=head1 path()

=head2 Description

Retrieves the path of a binary from a list of known binaries.

    my $mogrify_path = Cpanel::Binaries::path("mogrify");
    # $mogrify_path = "/usr/bin/mogrify"

    if ( -x $mogrify_path ) {
        # do what you need if mogrify is available and executable
    }

    # This will die
    Cpanel::Binaries::path("morgify"); # typo

This function will B<not> guarantee that the binary is available or that
it is executable. This is important because - while you can send it
"safely" to command runners (like C<qx>) and in backticks - it might not
work.

This function will only work on known binaries to handle developer typos.
If your binary is not available, you can also use L<Cpanel::FindBin>'s
C<findbin()>.

=head2 Arguments

=over

=item $binary (String)

=back

=head2 Returns

=over

=item C<$path> (String) - The path of the binary you requested, if found.

=back

=cut

sub path {
    my $binary = shift or return;

    if ( my $path = _get_thirdparty_binary_location($binary) ) {
        return $path . '/' . $binary;
    }

    my $bin_hash = system_bin_locations();
    if ( $bin_hash->{$binary} ) {
        return $bin_hash->{$binary} . '/' . $binary;
    }

    if ( my $dynamic_location = dynamic_bin_location($binary) ) {
        return $dynamic_location . '/' . $binary;
    }

    # Couldn't find it!
    require Carp;
    Carp::confess("Unknown binary: '$binary'; possible typo?");
}

# This code does not match the logic for path but seems to be of limited use.
# I've chosen not to keep it in sync since its logic seems to strip the bin path that would be relevant for system_bin_locations.
sub get_prefix {
    my $binary = shift or return;

    my $binloc = _get_thirdparty_binary_location($binary);
    return unless $binloc;
    $binloc =~ s{/bin$}{};
    return $binloc;
}

=pod

=head1 get_php_version()

=head2 Description

Provides the major and minor PHP version installed.

=head2 Arguments

=over

=item $args (Hash Ref)

=over

=item $flat (Boolean) - If true, the version string returned will not include periods.

=back

=back

=head2 Returns

=over

=item $version (String) - The major/minor version of PHP, with or without the period.

=back

=cut

sub get_php_version {
    my %args = @_;

    # Fallback to LEGACY_MAJOR when PHP_MAJOR not installed
    my $target_ver = _get_php_ver_only_for_testing('MAJOR');
    if ( !-x CPANEL_PHP_BIN . "/php" ) {
        $target_ver = _get_php_ver_only_for_testing('LEGACY');
    }

    return $target_ver if $args{flat};
    return join '.', split( '', $target_ver, 2 );
}

# The difficulty with constants is with mocking them out in tests.
# Dear reader, if you are reviewing this and know a better way, please
# point it out to me.
sub _get_php_ver_only_for_testing {
    return $_[0] eq 'MAJOR' ? PHP_MAJOR : PHP_LEGACY_MAJOR;
}

=head1 get_php_3rdparty_dir()

=head2 Description

Provides the path to the currently installed php version's libs & stuff:
/usr/local/cpanel/3rdparty/php/XX/ <-- This sub automagically figures the
'XX' for you

=head2 Returns

=over

=item $dir (String) - The directory.

=back

=cut

sub get_php_3rdparty_dir {
    my $ver = Cpanel::Binaries::get_php_version( 'flat' => 1 );
    return THIRD_PARTY . "/php/$ver/";
}

=pod

=head1 symlink_into_3rdparty_bin()

=head2 Description

Creates symlinks in THIRD_PARTY_BIN to all binaries from thirdparty_binary_locations() that are not actually located in THIRD_PARTY_BIN.

=head2 Arguments

None

=head2 Returns

None

=cut

sub symlink_into_3rdparty_bin {
    my $bin_loc_hash = thirdparty_binary_locations();
    my $optional     = { map { $_ => 1 } optional_binaries() };
    my $third_bin    = THIRD_PARTY_BIN;

    my $ok = 1;

    foreach my $binary ( keys %$bin_loc_hash ) {
        next if ( $bin_loc_hash->{$binary} eq $third_bin );
        next if ( $bin_loc_hash->{$binary} eq SYSTEM_BIN );

        my $third_bin_names = thirdparty_binary_names();
        my $real_binary     = $third_bin_names->{$binary};
        $real_binary ||= $binary;
        my $real_location = $bin_loc_hash->{$binary} . '/' . $real_binary;
        if ( !-e $real_location ) {
            LOG("WARNING: Unexpectedly missing $binary") unless $optional->{$binary};
            next;
        }

        my $third_bin_loc = "$third_bin/$binary";
        if ( -e $third_bin_loc || -l $third_bin_loc ) {
            my $points_to = readlink($third_bin_loc);
            next if ( $points_to && $points_to eq $real_location );
            LOG( "Removing $third_bin_loc, which " . ( $points_to ? "unexpectedly pointed to $points_to" : "was not a symlink" ) );
            unlink $third_bin_loc;
        }

        LOG("Linking $third_bin_loc -> $real_location");
        $ok = 0 unless symlink( $real_location, $third_bin_loc );
    }

    return $ok;
}

=pod

=head1 binaries_to_symlink_into_system_bin()

=head2 Description

Defines and provides the list of binaries from binaries_to_symlink_into_system_bin that we wish to symlink in /usr/bin if no file or symlink already exists.

=head2 Arguments

None

=head2 Returns

A subset of the binaries listed via thirdparty_binary_locations() that should have symlinks in /usr/bin if no file or symlink already exists.

=cut

sub binaries_to_symlink_into_system_bin {
    return [qw/git git-receive-pack git-shell git-upload-archive git-upload-pack/];
}

=pod

=head1 symlink_thirdparty_into_system_bin()

=head2 Description

Creates symlinks in /usr/bin to listed for items returned by binaries_to_symlink_into_system_bin() and creates a symlink if no file or symlink of that name exists in /usr/bin.

=head2 Arguments

None

=head2 Returns

=cut

sub symlink_thirdparty_into_system_bin {
    my $ok           = 1;
    my $to_link_ref  = binaries_to_symlink_into_system_bin();
    my $bin_loc_hash = thirdparty_binary_locations();

    foreach my $binary (@$to_link_ref) {
        my $third_bin_loc = SYSTEM_BIN . qq{/$binary};
        my $real_location = $bin_loc_hash->{$binary} . '/' . $binary;

        # only link if $third_bin_loc doesn't exist in any form and $real_location exists and is executable
        if ( !-e $third_bin_loc && -x $real_location ) {
            LOG("Linking $third_bin_loc -> $real_location");
            $ok = 0 unless symlink( $real_location, $third_bin_loc );
        }
    }

    return $ok;
}

1;
