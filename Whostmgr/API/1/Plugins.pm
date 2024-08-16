package Whostmgr::API::1::Plugins;

# cpanel - Whostmgr/API/1/Plugins.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Config::Constants             ();
use Cpanel::JSON                          ();
use Cpanel::Logger                        ();
use Cpanel::Locale                        ();
use Cpanel::Encoder::Tiny                 ();
use MIME::Base64                          ();
use Cpanel::SafeDir::RM                   ();
use Cpanel::SafeRun::Object               ();
use Cpanel::Signal::Defer                 ();
use Cpanel::Tar                           ();
use Cpanel::Version                       ();
use Cpanel::Themes                        ();
use Cpanel::Themes::Serializer::DynamicUI ();
use Cpanel::Daemonizer::Tiny              ();
use Cpanel::Plugins::Log                  ();

use Whostmgr::API::1::Utils              ();
use Whostmgr::Templates::Chrome::Rebuild ();

use constant NEEDS_ROLE => {
    check_rpms             => undef,
    generate_cpanel_plugin => undef,
    get_users_links        => undef,
    install_rpm_plugin     => undef,
    uninstall_rpm_plugin   => undef,
    update_cache           => undef,
    update_global_cache    => undef,
    update_lrv             => undef,
};

use constant LEGACY_PLUGIN_RPMS => (
    'cpanel-clamav',
    'cpanel-munin',
);

#overridden in tests?
our $update_lrv          = '/usr/local/cpanel/scripts/update_local_rpm_versions';
our $check_pkgs          = '/usr/local/cpanel/scripts/check_cpanel_pkgs';
our $update_cache        = '/usr/local/cpanel/bin/refresh_plugin_cache';
our $update_global_cache = '/usr/local/cpanel/bin/build_global_cache';

my ( $logger, $locale );

sub install_rpm_plugin {
    my ( $args, $metadata ) = @_;

    return _alter_rpm_installation( $args, $metadata, 'install', '--edit', 'installed' );
}

sub uninstall_rpm_plugin {
    my ( $args, $metadata ) = @_;

    return _alter_rpm_installation( $args, $metadata, 'uninstall', '--del' );
}

sub _alter_rpm_installation {
    my ( $args, $metadata, $action, $update_flag, @update_args ) = @_;

    my ($name) = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'name' );

    my ($reldir) = Cpanel::Plugins::Log::create_new( $name, CHILD_ERROR => '?' );

    $locale ||= Cpanel::Locale->get_handle;

    #1) Double-fork/exec to daemonize the installer.
    #
    #2) Daemonized process opens STDERR and STDOUT to the log.
    #
    #3) MODERN: The daemonized process itself does the install/uninstall,
    #   with exceptions and signals trapped and reported as appropriate.
    #
    #   LEGACY: The daemonized process fork()s again, and that last
    #   subprocess is what does the install/uninstall.
    #
    #4) The exit status of *those* subprocesses is what we put into
    #   the log metadata’s CHILD_ERROR.

    my $deferral = Cpanel::Signal::Defer->new(
        defer => {
            signals => [ () ],
            context => "plugin “$name” - $action",
        },
    );

    require Cpanel::Plugins;

    #TODO: Put this in a separate script so it’ll cross an exec() boundary
    #and free up memory.
    my $pid = Cpanel::Daemonizer::Tiny::run_as_daemon(
        sub {
            Cpanel::Plugins::Log::redirect_stdout_and_stderr($reldir);

            STDOUT->autoflush(1);
            STDERR->autoflush(1);

            my $chld_err;

            my $handler = sub {
                my ($sig) = @_;
                $sig      = 'ABRT' if $sig eq 'IOT';
                $chld_err = "SIG$sig";

                die "Received “$chld_err”; exiting!\n";
            };

            my @sigs = @{ Cpanel::Signal::Defer::NORMALLY_DEFERRED_SIGNALS() };

            try {
                if ( $action eq 'install' ) {
                    print $locale->maketext( "The system will install the “[_1]” plugin.", $name ) . "\n";
                }
                elsif ( $action eq 'uninstall' ) {
                    print $locale->maketext( "The system will uninstall the “[_1]” plugin.", $name ) . "\n";
                }

                #Legacy plugin installation
                if ( grep { $_ eq $name } LEGACY_PLUGIN_RPMS() ) {
                    my ($short_name) = $name =~ m<-(.+)>;

                    #We can’t do new_or_die() here because new_or_die()
                    #for SafeRun::Object brings in stdout.

                    my $run = Cpanel::SafeRun::Object->new(
                        program => $update_lrv,
                        args    => [ $update_flag => "target_settings.$short_name", @update_args ],
                        stdout  => \*STDOUT,
                        stderr  => \*STDERR,
                    );

                    die $run->autopsy() if $run->CHILD_ERROR();

                    $run = Cpanel::SafeRun::Object->new(
                        program => $check_pkgs,
                        args    => [ '--fix' => "--targets=$short_name" ],
                        stdout  => \*STDOUT,
                        stderr  => \*STDERR,
                    );

                    die $run->autopsy() if $run->CHILD_ERROR();

                    $run = Cpanel::SafeRun::Object->new(
                        program => $update_cache,
                        args    => [],
                        stdout  => \*STDOUT,
                        stderr  => \*STDERR,
                    );

                    die $run->autopsy() if $run->CHILD_ERROR();

                    $run = Cpanel::SafeRun::Object->new(
                        program => $update_global_cache,
                        args    => [],
                        stdout  => \*STDOUT,
                        stderr  => \*STDERR,
                    );

                    die $run->autopsy() if $run->CHILD_ERROR() && ( ( $run->CHILD_ERROR() >> 8 ) != 141 );
                }

                #Modern, YUM-based plugin installation
                else {
                    local @SIG{@sigs} = ($handler) x @sigs;

                    Cpanel::Plugins->can("${action}_plugins")->($name);
                }

                Whostmgr::Templates::Chrome::Rebuild::rebuild_whm_chrome_cache();

                if ( $action eq 'install' ) {
                    print $locale->maketext( "The system has completed the installation of the “[_1]” plugin.", $name ) . "\n";
                }
                elsif ( $action eq 'uninstall' ) {
                    print $locale->maketext( "The system has completed the removal of the “[_1]” plugin.", $name ) . "\n";
                }

                #If we got here, then great success! :)
                $chld_err = 0;
            }
            catch {
                try {
                    $chld_err = $_->get('signal_name');
                    $chld_err &&= "SIG$chld_err";
                    $chld_err ||= $_->get('error_code');
                };
                $chld_err ||= 1;

                print STDERR $_;
            }
            finally {
                Cpanel::Plugins::Log::set_metadata( $reldir, CHILD_ERROR => $chld_err );
            };
        }
    );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { pid => $pid, log_entry => $reldir };
}

sub get_users_links {
    my ( $args, $metadata ) = @_;

    my $user    = $args->{'user'};
    my $service = $args->{'service'} || 'cpaneld';

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return Cpanel::Themes::get_users_links( $user, $service );
}

sub generate_cpanel_plugin {
    my ( $args, $metadata ) = @_;

    $metadata->{'result'} = undef;
    $metadata->{'reason'} = undef;

    my $payload = {};

    $locale ||= Cpanel::Locale->get_handle;
    my $dir = _get_dir();

    my $name = $args->{'plugin_name'};
    if ( !defined $name || $name !~ m/\A[a-z0-9_-]+\z/ ) {
        $metadata->{result} = 0;
        $metadata->{reason} = $locale->maketext( 'The parameter “[_1]” must contain only lowercase letters, numbers, hyphens ([asis,-]), and underscores ([asis,_]).', 'plugin_name' );
    }
    else {

        # ? validate structure/contents?
        my $given_json;
        {
            local $Cpanel::IxHash::Modify = 'none';
            $given_json = $args->{'install.json'};
        }
        my $install_struct = eval { Cpanel::JSON::Load($given_json) };
        if ( !$install_struct ) {
            $logger ||= Cpanel::Logger->new;
            $logger->info("generate_cpanel_plugin install.json param error: $@");
            $metadata->{result} = 0;
            $metadata->{reason} = $locale->maketext( 'The parameter “[_1]” must be a valid [output,acronym,JSON,JavaScript Object Notation] string.', 'install.json' );
        }
        else {
            my $icon_struct;
            {
                local $Cpanel::IxHash::Modify = 'none';
                $icon_struct = eval { Cpanel::JSON::Load( $args->{'icons.json'} ) };
            }
            if ( !$icon_struct ) {
                $logger ||= Cpanel::Logger->new;
                $logger->info("generate_cpanel_plugin icons.json param error: $@");
                $metadata->{result} = 0;
                $metadata->{reason} = $locale->maketext( 'The parameter “[_1]” must be a valid [output,acronym,JSON,JavaScript Object Notation] string.', 'icons.json' );
            }
            elsif ( ref($icon_struct) ne 'HASH' || !keys %{$icon_struct} ) {
                $metadata->{result} = 0;
                $metadata->{reason} = $locale->maketext( 'The parameter “[_1]” is required and must be a non-empty [asis,hashref].', 'icons.json' );
            }
            else {
                if ( !-e $dir ) {
                    mkdir $dir, 0700;
                }

                my $pi_dir   = "$dir/$name";
                my $tar_name = "$name.tar.gz";
                my $tar_gz   = "$dir/$tar_name";
                if ( !$args->{overwrite} && ( -d $pi_dir || -e $tar_gz ) ) {
                    $metadata->{result} = 0;
                    $metadata->{reason} = $locale->maketext( 'There is already a plugin named “[_1]”.', $name );
                }
                else {

                    if ( $args->{overwrite} ) {
                        Cpanel::SafeDir::RM::safermdir($pi_dir) if -d $pi_dir;
                        unlink $tar_gz                          if -e $tar_gz;
                    }

                    my $entry_err;
                    if ( ref($install_struct) eq 'ARRAY' ) {    # ? error if not ?

                        my %id_lookup;
                        my $dynamic_ui = Cpanel::Themes::Serializer::DynamicUI->new( docroot => "/usr/local/cpanel/base/frontend/$Cpanel::Config::Constants::DEFAULT_CPANEL_THEME" );

                        for my $item_obj ( @{ $dynamic_ui->links() } ) {
                            $id_lookup{'link'}->{ $item_obj->{id} } = 1;
                        }

                        for my $group_obj ( @{ $dynamic_ui->groups() } ) {
                            $id_lookup{'group'}->{ $group_obj->{id} } = 1;
                        }

                        for my $entry ( @{$install_struct} ) {
                            next if ref($entry) ne 'HASH';    # ? error if not ?
                            if ( exists $id_lookup{ $entry->{type} }->{ $entry->{id} } && !$entry->{overwrite} ) {
                                $metadata->{result} = 0;
                                $metadata->{reason} = $locale->maketext( 'There is already an item with an [asis,id] of “[_1]”.', Cpanel::Encoder::Tiny::safe_html_encode_str( $entry->{id} ) );
                                $entry_err          = $entry->{id};
                                last;
                            }
                            delete $entry->{overwrite};       # do not write this to the data, if we last; and there are some remaining it is OK because that means we will not be writing the data
                            foreach my $k ( grep { $entry->{$_} eq '' } keys %{$entry} ) {
                                delete $entry->{$k};
                            }
                        }
                    }

                    if ( !defined $entry_err ) {
                        mkdir $pi_dir, 0700;

                        if ( open my $fh, '>', "$pi_dir/install.json" ) {
                            print {$fh} Cpanel::JSON::Dump($install_struct);    # since we modify out any 'overwrite' attr
                            close $fh;

                            chmod 0644, "$pi_dir/install.json";

                            my $icon_err;
                            my $icon_cnt = 0;
                            for my $filename ( keys %{$icon_struct} ) {
                                if ( $filename =~ m{(?:\.\.|[/<>*~])} ) {
                                    $metadata->{result} = 0;
                                    $metadata->{reason} = $locale->maketext( 'The file name “[_1]” contains invalid characters for a filename.', Cpanel::Encoder::Tiny::safe_html_encode_str($filename) );
                                    $icon_err           = 1;
                                    last;
                                }

                                if ( $filename !~ m/\.(?:png|svg)$/ ) {
                                    $metadata->{result} = 0;
                                    $metadata->{reason} = $locale->maketext( 'The file name “[_1]” is not a [list_or,_2] or [list_or,_3] image.', Cpanel::Encoder::Tiny::safe_html_encode_str($filename), ['.png'], ['.svg'] );
                                    $icon_err           = 1;
                                    last;
                                }

                                my $binary = $icon_struct->{$filename};
                                $binary =~ s/ /+/g;                              # ick due to FORM nasty
                                $binary =~ s{^data:image/\w+;base64,}{}i;
                                $binary =~ s{^data:image/svg\+xml;base64,}{}i;
                                my $base64_warn = '';
                                $binary = eval {
                                    local $SIG{__WARN__} = sub { $base64_warn = $_[0]; };
                                    MIME::Base64::decode_base64($binary);
                                };
                                if ( $@ || $base64_warn || !$binary ) {
                                    $logger ||= Cpanel::Logger->new;
                                    $logger->info("generate_cpanel_plugin icons.json key ($filename) error: -$@- -$base64_warn-");
                                    $metadata->{result} = 0;
                                    $metadata->{reason} = $locale->maketext( 'The content of “[_1]” is invalid.', Cpanel::Encoder::Tiny::safe_html_encode_str($filename) );
                                    $icon_err           = 1;
                                    last;
                                }

                                if ( open my $fh, '>', "$pi_dir/$filename" ) {
                                    print {$fh} $binary;
                                    close $fh;
                                    $icon_cnt++;
                                    chmod 0644, "$pi_dir/$filename";
                                }
                                else {
                                    $metadata->{result} = 0;
                                    my $html_safe_uploadpath = Cpanel::Encoder::Tiny::safe_html_encode_str("$pi_dir/$filename");
                                    $metadata->{reason} = $locale->maketext( 'Could not open “[_1]” for writing: [_2]', $html_safe_uploadpath, "$!" );
                                    $icon_err = 1;
                                    last;
                                }

                                # Add cPanel version and current date
                                my $cpversion = Cpanel::Version::get_version_text();
                                if ( open my $meta_fh, '>', "$pi_dir/meta.json" ) {
                                    print {$meta_fh} '[{"time":"' . time . '","cpversion":"' . $cpversion . '"}]';
                                    close $meta_fh;
                                    chmod 0644, "$pi_dir/meta.json";
                                }
                                else {
                                    $metadata->{result} = 0;
                                    my $html_safe_metajson = Cpanel::Encoder::Tiny::safe_html_encode_str("$pi_dir/meta.json");
                                    $metadata->{reason} = $locale->maketext( 'Could not open “[_1]” for writing: [_2]', $html_safe_metajson, "$!" );
                                    last;
                                }

                            }

                            if ( !$icon_err ) {
                                if ( system( Cpanel::Tar::load_tarcfg()->{'bin'}, '-C', $dir, '-c', '-z', '-f', $tar_gz, $name ) == 0 ) {
                                    $metadata->{result} = 1;
                                    $metadata->{reason} = $locale->maketext( 'The system successfully created an archive of the “[_1]” plugin.', $name );
                                    $payload->{tarball} = $tar_name;
                                    $payload->{mtime}   = ( stat($tar_gz) )[9];
                                }
                                else {
                                    $logger ||= Cpanel::Logger->new;
                                    $logger->info( 'generate_cpanel_plugin `' . join( " ", Cpanel::Tar::load_tarcfg()->{'bin'}, '-C', $dir, '-c', '-z', '-f', $tar_gz, $name ) . "` did not exit cleanly: $?" );
                                    $metadata->{result} = 0;
                                    $metadata->{reason} = $locale->maketext( 'The system could not create the file “[_1]”.', "$name.tar.gz" );
                                }
                            }
                        }
                        else {
                            $metadata->{result} = 0;
                            $metadata->{reason} = $locale->maketext( 'Could not open “[_1]” for writing: [_2]', "$pi_dir/install.json", "$!" );
                        }
                    }
                    Cpanel::SafeDir::RM::safermdir($pi_dir);    # ? unless DEBUG ?
                }
            }
        }
    }

    return $payload;
}

# for testing purposes
sub _get_dir { return '/var/cpanel/cpanel_plugin_generator'; }

1;
