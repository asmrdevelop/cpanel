package Cpanel::ApacheConf::Rebuild;

# cpanel - Cpanel/ApacheConf/Rebuild.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::ApacheConf::Rebuild

=head1 SYNOPSIS

  Perform a rebuild of the Apache configuration using the system configuration
  and userdata.

=cut

use Cpanel::Debug                         ();
use Cpanel::Transaction                   ();
use Cpanel::Finally                       ();
use Cpanel::Rand                          ();
use Cpanel::ConfigFiles::Apache::Generate ();
use Cpanel::ConfigFiles::Apache::Syntax   ();
use Cpanel::Config::Httpd::EA4            ();
use Cpanel::Autodie                       qw( rename unlink_if_exists );
use Cpanel::PwCache                       ();

our $LOCK    = 0;
our $NO_LOCK = 1;

our $data_store_dir = '/var/cpanel/conf/apache/';

=head2 rebuild_full_http_conf($apache_conf)

Rebuild a brand new httpd.conf using the system configuration
and userdata.  A lock is held on the configuration file
to ensure no other process modifies the file during the
rebuild process.

=over 2

=item Input

=over 3

=item $apache_conf C<SCALAR>

    The path to the apache configuration file (httpd.conf)

=back

=item Output

=over 3

Returns 1 on success and dies on failure.

=back

=back

=cut

sub rebuild_full_http_conf {
    my ( $apache_conf, $force, $lock ) = @_;

    _import_and_archive_distiller_data();

    $lock //= $LOCK;    # if unspecified, lock

    if ( !Cpanel::Config::Httpd::EA4::is_ea4() ) {
        die 'This tool is unavailable until EasyApache installs Apache.';
    }

    my $release_lock;
    if ( $lock == $NO_LOCK ) {

        # ServiceManager can rebuild if a restart fails.  At this point it will
        # already have a lock so we may be called with --no-lock
    }
    else {
        # Lock httpd.conf first
        my ( $lock_ok, $httpd_conf_transaction ) = Cpanel::Transaction::get_httpd_conf();
        Cpanel::Debug::log_die("Could not lock Apache configuration: $httpd_conf_transaction") if !$lock_ok;

        $release_lock = Cpanel::Finally->new(
            sub {
                # Now release the lock
                my ( $abort_ok, $abort_msg ) = $httpd_conf_transaction->abort();
                die $abort_msg if !$abort_ok;

            }
        );
    }

    my $test_httpd_conf = Cpanel::Rand::get_tmp_file_by_name($apache_conf);
    die 'Failed to get a temporary working file!' if ( $test_httpd_conf eq '/dev/null' );

    my $leave_tmp;

    my $remove_tmp = Cpanel::Finally->new(
        sub {
            if ( !$leave_tmp ) {
                Cpanel::Autodie::unlink_if_exists($test_httpd_conf);
            }
        },
    );

    my $ref = _try_rebuild( $test_httpd_conf, 1 );

    if ( !$ref->{status} ) {    # issafe
        warn <<"EOM";
Initial configuration generation failed with the following message:

$ref->{message}
Rebuilding configuration without any local modifications.

EOM

        $ref = _try_rebuild( $test_httpd_conf, 0 );

        if ( !$ref->{status} ) {
            $leave_tmp = 1;

            die <<"EOM";
Failed to generate a syntactically correct Apache configuration.
Bad configuration file located at $test_httpd_conf
Error:
$ref->{message}

EOM
        }
    }

    # Great success, the lock will be released
    # when the Cpanel::Finally object is DESTROYed
    Cpanel::Autodie::rename( $test_httpd_conf, $apache_conf );

    return 1;
}

sub _try_rebuild {
    my ( $test_httpd_conf, $local ) = @_;

    my $res = Cpanel::ConfigFiles::Apache::Generate::generate_config_file( { path => $test_httpd_conf, local => $local } );    # issafe

    if ( !$res->{status} ) {
        die "Failed to build Apache configuration file ($test_httpd_conf)\n$res->{message}\n";
    }

    return Cpanel::ConfigFiles::Apache::Syntax::check_syntax($test_httpd_conf);
}

###############
#### helpers ##
###############

sub _get_old_std_keys_hash {
    my %_old_std_keys = (

        # simple attributes are added automatically.
        # in case the old name does not match the new attribute name
        # but is still a simple item we could do `oldname => "newname"`
        # otherwise a codref can do the needful.

        rlimitcpu => sub {
            my ( $new, $old ) = @_;
            $new->{rlimit_cpu_hard} = $old->{rlimitcpu}{item}{maxrlimitcpu};
            $new->{rlimit_cpu_soft} = $old->{rlimitcpu}{item}{softrlimitcpu};
        },

        rlimitmem => sub {
            my ( $new, $old ) = @_;
            $new->{rlimit_mem_hard} = $old->{rlimitmem}{item}{maxrlimitmem};
            $new->{rlimit_mem_soft} = $old->{rlimitmem}{item}{softrlimitmem};
        },

        logformat => sub {
            my ( $new, $old ) = @_;
            for my $item ( @{ $old->{logformat}{items} } ) {
                if ( $item->{logformat} =~ m/ (combined|common)$/ ) {
                    my $type = $1;
                    $new->{"logformat_$type"} = $item->{logformat};
                }
            }
        },

        directory => sub {
            my ( $new, $old ) = @_;
            $new->{root_options} = $old->{directory}{options}{item}{options};
        },
    );

    for my $key ( @{ Cpanel::EA4::Conf->instance->conf_attrs } ) {
        next if $key eq "root_options";
        next if exists $_old_std_keys{$key};
        $_old_std_keys{$key} = "";
    }

    return %_old_std_keys;
}

sub _import_and_archive_distiller_data {
    if ( -s "$data_store_dir/main" || -s "$data_store_dir/local" ) {
        require Cpanel::EA4::Conf;

        # Migrate old distiller data to the simplified ea4 data
        my $e4c       = Cpanel::EA4::Conf->instance;
        my $distiller = _load_legacy_distiller_data( "$data_store_dir/main", "$data_store_dir/local" );

        for my $name ( keys %{$distiller} ) {
            next if $name eq 'serveradmin' || $name eq 'servername' || $name eq 'sslprotocol_list_str';    # read-only
            my $value = $distiller->{$name};

            eval { $e4c->$name($value) };
            if ($@) {
                warn "The distiller value for “$name” ($value) is invalid and will not be migrated to “$Cpanel::EA4::Conf::CONFPATH”: $@\n";
            }
        }

        eval { $e4c->save };
        if ($@) {
            warn "Failed to save “$Cpanel::EA4::Conf::CONFPATH”: $@n";
        }
        else {
            _clean_ea3_distiller_files();
        }
    }

    return 1;
}

sub _load_legacy_distiller_data {
    my @yaml_files    = @_;
    my $normalized_hr = {};

    for my $yaml_file (@yaml_files) {
        _add_yaml_file_to_hr( $yaml_file, $normalized_hr );
    }

    return $normalized_hr;
}

sub _add_yaml_file_to_hr {
    my ( $yaml_file, $normalized_hr ) = @_;

    require Cpanel::YAML;
    my $main = eval { Cpanel::YAML::LoadFile($yaml_file)->{main} };
    if ( !$@ && defined $main ) {

        my %old_std_keys = _get_old_std_keys_hash();

        # add $main to $normalized_hr
        for my $old_std_name ( keys %old_std_keys ) {
            next if !exists $main->{$old_std_name};
            if ( ref $old_std_keys{$old_std_name} ) {
                $old_std_keys{$old_std_name}->( $normalized_hr, $main );
            }
            else {
                my $new_name = defined $old_std_keys{$old_std_name} && length $old_std_keys{$old_std_name} ? $old_std_keys{$old_std_name} : $old_std_name;    # in case the old name does not match the new attribute name
                $normalized_hr->{$new_name} = $main->{$old_std_name}{item}{$old_std_name};
            }
        }
    }

    return;
}

sub _clean_ea3_distiller_files {
    my @distiller_files = qw(
      /var/cpanel/conf/apache/success
      /var/cpanel/conf/apache/main
      /var/cpanel/conf/apache/main.cache
      /var/cpanel/conf/apache/local
      /var/cpanel/conf/apache/local.cache
      /var/cpanel/templates/apache1
      /var/cpanel/templates/apache1_3
      /var/cpanel/templates/apache2
      /var/cpanel/templates/apache2_0
      /var/cpanel/templates/apache2_2
    );

    my @existing_distiller_files = grep { -l $_ || -e _ } @distiller_files;
    if (@existing_distiller_files) {
        my $homedir        = Cpanel::PwCache::gethomedir() || '/root';
        my $tarball        = "$homedir/legacy_ea3_distiller_files-" . time() . ".tar.gz";
        my @relative_paths = map { my $c = $_; $c =~ s{^/}{}; $c } @existing_distiller_files;
        system qw(/bin/tar czf), $tarball, qw(-C /), @relative_paths;

        if ($?) {
            warn "Failed to archive legacy ea3 distiller files ($?)\n";
        }
        else {
            print "The following files were archived to $tarball:\n";

            for my $path (@existing_distiller_files) {
                print "    • $path\n";

                if ( -l $path || !-d _ ) {
                    unlink($path);
                    warn "Could not remove “$path” (this will need done manually): $!\n" if -l $path || -e $path;
                }
                else {
                    require Cpanel::SafeDir::RM;
                    Cpanel::SafeDir::RM::safermdir($path);
                    warn "Could not remove “$path” (this will need done manually): $!\n" if -d $path;
                }
            }
        }
    }

    return;
}

1;
