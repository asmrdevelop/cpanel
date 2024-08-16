package Cpanel::EA4::Util;

# cpanel - Cpanel/EA4/Util.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Env             ();
use Cpanel::SafeRun::Errors ();
use Try::Tiny;

our $ea4_metainfo_file = "/etc/cpanel/ea4/ea4-metainfo.json";

# This method checks if the current system is compatible with EA4.
# EA4 currently supports only:
# 	- CentOS systems with version 6 and above.
sub is_os_ea4_compatible {
    return 1;
}

my $available_php_versions_ar;
my %seen_php_ver;

sub get_available_php_versions {
    require Cpanel::PackMan;
    $available_php_versions_ar //= [
        sort
          map {
            my $v;
            my $p = $_;
            if ( $p =~ m/\w+-php(\d)(\d)-php-common/ ) {
                $v = "$1.$2";
                $v = undef if $seen_php_ver{$v}++;
            }

            $v ? ($v) : ();
          } Cpanel::PackMan->instance->list( prefix => "*-php*-php-common" )
    ];

    return @{$available_php_versions_ar};
}

sub get_default_php_version {
    my ( $ver, $pkg );
    require Cpanel::JSON;
    my $hr = eval { Cpanel::JSON::LoadFile($ea4_metainfo_file) };
    if ( $@ || !$hr->{default_php_package} ) {
        $ver = ( get_available_php_versions() )[-1];    # get the newest
    }
    else {
        $pkg = $hr->{default_php_package};
    }

    if ( $pkg && $pkg =~ m/php(\d)(\d)$/ ) {
        $ver = "$1.$2";
    }

    return $ver;
}

sub get_default_php_handler {
    require Cpanel::JSON;
    my $hr = eval { Cpanel::JSON::LoadFile($ea4_metainfo_file) };

    if ( $@ || !$hr->{default_php_handler} ) {
        return "cgi";
    }
    else {
        return $hr->{default_php_handler};
    }

    return;
}

our $current_php_version;
our $php_bin = '/usr/bin/php';

sub get_current_php_version {
    return $current_php_version if $current_php_version;
    return                      if !-x $php_bin;

    try {
        Cpanel::Env::cleanenv();

        # When called via WHM (cpsrvd), the php binary thinks it needs to be in CGI mode so we have to pass it off this way
        local $ENV{'SCRIPT_FILENAME'} = '/usr/local/cpanel/php/report_version.php';
        my $output = Cpanel::SafeRun::Errors::saferunallerrors( $php_bin, '-n', '-v', '-d', 'cgi.force_redirect=0' );

        # Under CLI, this will print the version at the front sue to -v flag, under CGI it will print version at end due to script execution
        if ( $output =~ m/^PHP\s+(\d+\.\d+)\.\d+/ms ) {
            $current_php_version = $1;
        }
        elsif ( $output =~ m/PHP (\d+\.\d+)\.\d+$/ms ) {
            $current_php_version = $1;
        }
    };
    return $current_php_version;
}

sub get_target_php_version {
    my ($current) = @_;
    my %ea4_lu;
    @ea4_lu{ get_available_php_versions() } = ();
    return ( exists $ea4_lu{$current} ? $current : get_default_php_version() );
}

sub profile_appears_valid {
    my ($file) = @_;

    return if !$file;
    return if $file !~ m/\.json\z/;
    return if ( !-e $file || -z _ );

    require Cpanel::JSON;
    my $hr = eval { Cpanel::JSON::LoadFile($file) };
    return if $@;
    return if !exists $hr->{pkgs};    # TODO/YAGNI? verify other fields are there?
    return if !@{ $hr->{pkgs} };

    return 1;
}

1;
