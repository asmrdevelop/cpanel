
# cpanel - Cpanel/PHPFPM/Inventory.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::PHPFPM::Inventory;

use strict;
use warnings;

use Cpanel::FileUtils::Dir              ();
use Cpanel::Config::userdata::Constants ();
use Cpanel::Config::userdata::Cache     ();
use Cpanel::LoadFile                    ();
use Cpanel::SysQuota                    ();
use Cpanel::PHPFPM::Constants           ();    # PPI USE OK - used for $Cpanel::PHPFPM::Constants::opt_cpanel

use constant FIELD_PHP_VERSION => $Cpanel::Config::userdata::Cache::FIELD_PHP_VERSION;

sub _is_conf_file_generated_by_cpanel {
    my ($file) = @_;

    my $is_generated = 0;
    my $fh;

    if ( open $fh, '<', $file ) {
        while (<$fh>) {
            chomp;
            if ( index( $_, 'cPanel FPM Configuration' ) >= 0 ) {
                $is_generated = 1;
                last;
            }
        }
        close $fh;
    }

    return $is_generated;
}

# this routine is for troubleshooting and QA test support

sub get_inventory {
    my $userdata_dir = $Cpanel::Config::userdata::Constants::USERDATA_DIR;
    my @users        = grep { $_ ne 'nobody' } @{ Cpanel::FileUtils::Dir::get_directory_nodes($userdata_dir) };
    my %inventory;
    my %alldomains;

    $inventory{'cruft'} = { 'yaml_files' => [], 'conf_files' => [] };

    my $over_quota_hr  = _get_overquota();
    my $userdata_cache = Cpanel::Config::userdata::Cache::load_cache();

    foreach my $user (@users) {
        $inventory{$user}{'place_holder'} = 1;

        my $current_dir = "$userdata_dir/$user";

        # Tolerate failures to read $current_dir.
        local $@;
        my @yamls = eval {

            # If $user no longer exists, then $current_dir will be gone.
            # We tolerate that scenario without considering it a failure.
            #
            my $nodes_ar = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists($current_dir);
            $nodes_ar ||= [];

            grep { index( $_, '.php-fpm.yaml' ) > -1 && substr( $_, -13 ) eq '.php-fpm.yaml' } @$nodes_ar;
        };

        # Report any failure that may have happened:
        warn if $@;

        my $domains = {};

        # is user over quota?

        my $is_overquota = $over_quota_hr->{$user} ? 1 : 0;

        foreach my $file (@yamls) {
            if ( $file =~ m/^(.+)\.php-fpm\.yaml$/ ) {
                my $domain = $1;

                $alldomains{$domain} = {
                    'user'         => $user,
                    'domain'       => $domain,
                    'file'         => $file,
                    'dir'          => "$userdata_dir/$user",
                    'yaml_path'    => "$userdata_dir/$user/$file",
                    'count'        => 0,
                    'conf_files'   => [],
                    'is_overquota' => $is_overquota,
                };

                $domains->{$domain} = $alldomains{$domain};

                my $php_version;

                if ( $userdata_cache->{$domain} && $userdata_cache->{$domain}->[FIELD_PHP_VERSION] ) {
                    $php_version = $userdata_cache->{$domain}->[FIELD_PHP_VERSION];
                }
                else {
                    push( @{ $inventory{'cruft'}->{'yaml_files'} }, "$current_dir/$file" );
                }

                $alldomains{$domain}->{"phpversion"} = $php_version;
            }
        }

        $inventory{$user}->{'domains'} = $domains;
    }

    # now scan php-fpm.d dirs

    my @conf_files = glob("${Cpanel::PHPFPM::Constants::opt_cpanel}/ea-php??/root/etc/php-fpm.d/*.conf");
    my @orphaned_files;

    foreach my $file (@conf_files) {
        my $idx       = rindex( $file, '/' );
        my $conf_file = substr( $file, $idx + 1 );
        $idx = rindex( $conf_file, "." );

        # get socket name

        my $socket_name = "_unknown_";
        eval {
            my $content = Cpanel::LoadFile::loadfile($file);
            my @lines   = split( /\n/, $content );

            # listen = #/opt/cpanel/ea-php55/root/usr/var/run/php-fpm/8b54c1cb37a8a00661225ba80ac5f7254aaa91ab.sock
            my @listen = grep { index( $_, 'listen' ) > -1 && m/^\s*listen\s*=/ } @lines;
            if (@listen) {
                if ( $listen[0] =~ m/^\s*listen\s*=\s*(.*)\s*$/ ) {
                    $socket_name = $1;
                }
            }
        };

        my $domain = substr( $conf_file, 0, $idx );

        my $ref;

        $ref = $alldomains{$domain} if exists $alldomains{$domain};

        if ( !defined $ref ) {
            if ( _is_conf_file_generated_by_cpanel($file) ) {
                push( @{ $inventory{'cruft'}->{'conf_files'} }, $file );
            }
            else {
                push( @orphaned_files, $file );
            }
        }
        else {
            my $phpversion = $ref->{'phpversion'};
            $ref->{'count'}++;

            my $conf_mtime = ( stat($file) )[9];
            my $yaml_mtime = ( stat( $ref->{'yaml_path'} ) )[9];

            my $conf_ref = {
                'file'       => $file,
                'conf_mtime' => $conf_mtime,
                'yaml_mtime' => $yaml_mtime,
                'yaml_path'  => $ref->{'yaml_path'},
                'status'     => 1,
                'msg'        => 'MTIME CORRECT',
                'socket'     => $socket_name,
            };

            $conf_ref->{'socket_status'} = "Success";
            $conf_ref->{'socket_status'} = "Error" if ( !-S $socket_name );

            if ( !defined $phpversion || !( $file =~ m/$phpversion/ ) ) {
                $conf_ref->{'status'} = 0;
                $conf_ref->{'msg'}    = 'INVALID PHP VERSION',
                  $conf_ref->{'msg'} = $phpversion if ( defined $phpversion && $phpversion =~ m/ORPHAN/ );

                push( @{ $ref->{'conf_files'} }, $conf_ref );
            }
            else {
                if ( $yaml_mtime > $conf_mtime ) {
                    $conf_ref->{'status'} = 0;
                    $conf_ref->{'msg'}    = "ERROR CONF IS OLDER THAN YAML";
                }

                push( @{ $ref->{'conf_files'} }, $conf_ref );
            }
        }
    }

    $inventory{'orphaned_files'} = \@orphaned_files;

    return \%inventory;
}

sub fix_cruft {
    my $renamed_files;

    my $fpm_inventory = get_inventory();
    my @cruft         = ( @{ $fpm_inventory->{'cruft'}->{'yaml_files'} }, @{ $fpm_inventory->{'cruft'}->{'conf_files'} } );

    my $time = time;

    foreach my $file (@cruft) {
        local $!;
        if ( _rename_conf( $file, "$file.$time.invalid" ) ) {
            $renamed_files->{$file}{new} = "$file.$time.invalid";
        }
        else {
            $renamed_files->{$file}{error} = $!;
        }
    }

    return $renamed_files;
}

sub _rename_conf {
    return rename( $_[0], $_[1] );
}

sub _get_overquota {

    # user quota information
    my ( $used_hr, $limit_hr ) = Cpanel::SysQuota::analyzerepquotadata();
    my %over_quota;

    foreach my $user ( sort ( keys %$used_hr, keys %$limit_hr ) ) {
        next if exists $over_quota{$user};
        $over_quota{$user} = 0;
        next                   if !exists $used_hr->{$user} || !exists $limit_hr->{$user};
        $over_quota{$user} = 1 if ( $used_hr->{$user} >= $limit_hr->{$user} );
    }
    return \%over_quota;
}

1;
