package Cpanel::TailWatch;

# cpanel - Cpanel/TailWatch.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

require Cpanel::Config::LoadCpConf::Micro;
require Cpanel::Config::LoadUserDomains::Tiny;
require Cpanel::Fcntl;
require Cpanel::Hostname;
require Cpanel::Time::Local;
require Cpanel::IP::Loopback;
require IO::Handle;

use Getopt::Param::Tiny                  ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::Timezones::SubProc           ();
use Cpanel::Sys::Chattr                  ();
use Cpanel::Server::Type                 ();
use Cpanel::Server::Type::Profile::Roles ();
use Cpanel::Autodie                      ();
use Cpanel::Systemd::Notify::Boot        ();

my $logger;
my $pid_fh;
our $Inotify = 0;
our $VERSION = 1.2;

my $MAX_LINES_TO_PROCESS_ONE_LOOP = 4096;

our $TAILWATCH_OBJECT_FULL  = 0;
our $TAILWATCH_OBJECT_EMPTY = 1;
our $TAILWATCH_OBJECT_TINY  = 2;

# class method or object method
sub get_driver_hashref {
    my ($self) = @_;

    my @enabled_modules;
    my %drivers;

    if ( ref($self) && exists $self->{'enabled_modules'} ) {

        # An object already has the data we want
        @enabled_modules = @{ $self->{'enabled_modules'} };
    }
    else {

        # class method calls have to figure out the data that the object
        # would have but without inititaing the driver objects.
        if ( opendir( my $tail_dh, tail_watch_driver_dir() ) ) {
            while ( my $file = readdir($tail_dh) ) {
                next if ( $file !~ /\.pm$/ );
                my @pb  = split( /\//, $file );
                my $mod = pop(@pb);
                $mod =~ s/\.pm$//g;
                next if $mod eq 'Base';

                my $mod_conf_name = lc($mod);
                my $ns            = 'Cpanel::TailWatch::' . $mod;
                my $config_ns     = 'Cpanel::TailWatch::' . $mod . '::Config';

                my $is_enabled;
                my $managed                  = 1;
                my $available_for_dnsonly    = 0;
                my $available_for_wp_squared = 1;
                my $description              = '';

                ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
                eval 'local $SIG{__DIE__}; local $SIG{__WARN__}; require ' . $config_ns . ';';

                if ($@) {
                    require Cpanel::Logger;
                    $logger ||= Cpanel::Logger->new();
                    $logger->warn("Could not load config for $config_ns ($@): $!");
                }
                else {
                    if ( my $dnsonly_coderef = "$config_ns"->can('available_for_dnsonly') ) {
                        $available_for_dnsonly = $dnsonly_coderef->( $ns, $self );
                    }

                    next if ( !$available_for_dnsonly && Cpanel::Server::Type::is_dnsonly() );

                    if ( my $get_roles = "$config_ns"->can('REQUIRED_ROLES') ) {
                        my $required_roles    = $get_roles->() // [];
                        my $can_enable_driver = 1;
                        foreach my $role (@$required_roles) {
                            if ( !Cpanel::Server::Type::Profile::Roles::is_role_enabled($role) ) {
                                $can_enable_driver = 0;
                                last;
                            }
                        }
                        next unless $can_enable_driver;
                    }

                    if ( my $managed_coderef = "$config_ns"->can('is_managed_by_tailwatchd') ) {
                        $managed = $managed_coderef->( $ns, $self );
                    }
                    if ( my $description_coderef = "$config_ns"->can('description') ) {
                        $description = $description_coderef->( $ns, $self );
                    }
                    if ( my $is_enabled_coderef = "$config_ns"->can('is_enabled') ) {
                        $is_enabled = $is_enabled_coderef->( $ns, $self );
                    }
                }

                if ( !defined $is_enabled ) {
                    $is_enabled = ( $self->has_chkservd_disable_file($mod_conf_name) || $self->is_skipped_in_cpconf($mod_conf_name) ) ? 0 : 1;
                }
                push @enabled_modules, [ $ns, $is_enabled, $managed, $description ];

                # We do not actually want to laod the modules as we are likely running though a config screen in whm
            }
            closedir($tail_dh);
        }
        else {
            require Cpanel::Logger;
            $logger ||= Cpanel::Logger->new();
            $logger->warn( "Could not read directory “" . tail_watch_driver_dir() . "”: $!" );
        }
    }

    foreach my $driver (@enabled_modules) {
        my $display_name = $driver->[0];
        $display_name =~ s/Cpanel::TailWatch:://;

        $drivers{$display_name} = {
            'value'       => $driver->[0],
            'disabled'    => ( $driver->[1] ? 0 : 1 ),    # Needed for legacy
            'enabled'     => ( $driver->[1] ? 1 : 0 ),
            'managed'     => $driver->[2],
            'description' => $driver->[3],
            'dnsonly'     => $driver->[4],
        };
    }

    return \%drivers;
}

sub new {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my $class   = shift;
    my $self    = bless {}, $class;
    my $args_hr = shift;

    $self->_load_defaults();

    return $self if exists $args_hr->{'type'} && $args_hr->{'type'} == $TAILWATCH_OBJECT_EMPTY;
    $self->{'FILELIST'}         = {};
    $self->{'POSITIONS_SYNCED'} = 0;

    $self->_create_data_cache();

    $self->{'global_share'}{'objects'}{'param_obj'} = exists $args_hr->{'param_obj'} ? $args_hr->{'param_obj'} : '';
    if ( !$self->{'global_share'}{'objects'}{'param_obj'} ) {
        $self->{'global_share'}{'objects'}{'param_obj'} = Getopt::Param::Tiny->new( { 'array_ref' => [] } );
    }

    $self->{'max_open_filedescriptors'} = abs( int( $self->{'global_share'}{'objects'}{'param_obj'}->param('max-fd') || 0 ) );
    $self->debug("Max Open File Descriptors flag: $self->{'max_open_filedescriptors'}");

    if ( !$self->{'max_open_filedescriptors'} && exists $self->{'global_share'}{'data_cache'}{'cpconf'}{'tailwatchd_max_fd'} ) {
        $self->{'max_open_filedescriptors'} ||= abs( int( $self->{'global_share'}{'data_cache'}{'cpconf'}{'tailwatchd_max_fd'} || 2048 ) );
        $self->debug("Max Open File Descriptors config: $self->{'max_open_filedescriptors'}");
    }
    $self->{'max_open_filedescriptors'} ||= 100;

    $self->debug("Max Open File Descriptors set to $self->{'max_open_filedescriptors'}");
    if ( $self->{'global_share'}{'objects'}{'param_obj'} && $self->{'global_share'}{'objects'}{'param_obj'}->param('trace') ) {
        $self->{'trace'}                        = $self->{'global_share'}{'objects'}{'param_obj'}->param('trace');
        $self->{'data_cache'}{'trace'}{'count'} = 0;
        $self->{'data_cache'}{'trace'}{'limit'} = int( $self->{'global_share'}{'objects'}{'param_obj'}->param('trace') ) || 10000;
    }
    if ( $self->{'global_share'}{'objects'}{'param_obj'} && $self->{'global_share'}{'objects'}{'param_obj'}->param('debug') ) {
        $self->{'debug'} = $self->{'global_share'}{'objects'}{'param_obj'}->param('debug');
    }

    return $self if exists $args_hr->{'type'} && $args_hr->{'type'} == $TAILWATCH_OBJECT_TINY;

    # Only load the user map when we don't want a
    # TINY object as its expensive.
    $self->_load_user_map();

    if ( exists $INC{'Linux/Inotify2.pm'} ) {    #This is loaded in the libexec/tailwatch/tailwatchd file
        my $inotify = Linux::Inotify2->new();
        if ($inotify) {
            $self->info("inotify mode is enabled");
            $self->{'inotify'} = $inotify;
            $inotify->blocking(0);
            $Cpanel::TailWatch::Inotify = 1;
        }
        else {
            $self->info("inotify support not available (could not create inotify object)");
        }
    }
    elsif ( -e '/var/cpanel/conserve_memory' ) {

        # This is an assumption based on how Cpanel::Inotify::Wrap::load works.  If that
        # behavior changes, this may have to, too.
        $self->info("Configured to conserve memory; skipped load of Linux::Inotify2.");
    }
    else {
        $self->info("inotify support not available (Linux::Inotify2 missing or non-functional)");
    }

    opendir( my $tail_dir, tail_watch_driver_dir() );
    while ( my $file = readdir($tail_dir) ) {
        next if ( $file !~ /\.pm$/ );
        my @pb  = split( /\//, $file );
        my $mod = pop(@pb);
        $mod =~ s/\.pm$//g;
        next if $mod eq 'Base';

        my $mod_conf_name = lc($mod);
        if ( $self->has_chkservd_disable_file($mod_conf_name) || $self->is_skipped_in_cpconf($mod_conf_name) ) {
            push @{ $self->{'enabled_modules'} }, [ "Cpanel::TailWatch::$mod", 0 ];
            next;
        }

        my $load_with_opts;
        if ( ref $args_hr && ref $args_hr->{load_modules} && $args_hr->{load_modules}->{$mod} ) {
            $load_with_opts = $args_hr->{load_modules}->{$mod};
        }

        if ( ( my ( $status, $ns, $file, $req, $obj ) = $self->_load_module( $mod, $load_with_opts ) )[0] ) {
            my $do_sql_warning = 1;
            my $file           = $self->has_sql_file($ns);
            if ( $file && $obj ) {

                # if driver supports importing contents of sql log, attempt to do so
                if ( $ns->can('import_sql_file') ) {
                    $do_sql_warning = $obj->import_sql_file($file) ? 0 : 1;
                }
            }

            if ( $do_sql_warning && -t STDIN && $file ) {

                my ($database) = reverse( split( /\//, $file ) );
                $database =~ s{\.sql$}{};    # db name is same as file (IE same as lc() NS)

                # if not the driver should tell us
                if ( my $get_name = $ns->can('get_database_name') ) {
                    if ($obj) {
                        $database = $obj->get_database_name();
                    }
                    else {
                        $database = $get_name->($ns);
                    }
                }

                # if the driver didn't return specifics then we default to generic
                $database ||= 'DATABASE_NAME_HERE';

                my $msg = <<"END_SQL_MSG";
$ns appears to have unprocessed SQL in $file.

When sqlite is unable to execute a query they are logged for processing later.

Eventually these SQL files may be handled automatically and this message will not appear.

In the meantime you can execute the queries as root with something like this:

  mv $file $file.tmp_working_copy
  /scripts/restartsrv_tailwatchd
  /usr/local/cpanel/3rdparty/bin/sqlite3 $database < $file.tmp_working_copy

Once you are sure all is well you can remove $file.tmp_working_copy
END_SQL_MSG
                $self->alert($msg);
            }

        }
        else {
            $self->alert( "The tailwatchd driver '$ns' ($req) failed to load", $@ ) if $@;
        }
    }
    closedir($tail_dir);

    $self->{'starttime'}       = time;
    $self->{'starttime_human'} = localtime( $self->{'starttime'} );

    # FOR DEBUG
    #$SIG{'USR1'} = sub {
    #        require Data::Dumper;
    #        $self->log( Data::Dumper::Dumper($self) );
    #        $self->log( Data::Dumper::Dumper( \%INC ) );
    #    };

    return $self;
}

sub _load_defaults {
    my $self = shift;
    $self->{'zero_name'}            = 'tailwatchd';
    $self->{'max_mem'}              = ( 128 * ( 1024 * 1024 ) );
    $self->{'pid_file'}             = '/var/run/tailwatchd.pid';
    $self->{'log_file'}             = '/usr/local/cpanel/logs/tailwatchd_log';
    $self->{'hasSIG'}               = 0;
    $self->{'hasSIGTERM'}           = 0;
    $self->{'hasSIGUSR1'}           = 0;
    $self->{'MAX_ACTION_WAIT_TIME'} = 2000;                                      #time before inotify timeout (will be adjusted down by modules we load)
    return;
}

sub alert {
    my ( $self, $friendly, $system ) = @_;
    return if $ENV{'TAP_COMPLIANT'};

    if ($system) {
        $friendly .= "\n\nMore specifically:\n\n\t$system";
    }

    my $error = <<"END_ERROR";

!!
ATTENTION ATTENTION ATTENTION ATTENTION

$friendly

ATTENTION ATTENTION ATTENTION ATTENTION
!!

END_ERROR
    print $error;
    return $self->log($error);
}

sub trace {
    my ( $self, $driver, $line ) = @_;
    return if !$self->{'trace'};

    return if $self->{'data_cache'}{'trace'}{'count'} > $self->{'data_cache'}{'trace'}{'limit'};
    chomp($line);
    my $now = localtime(time);
    $self->log("[trace $driver $now] $line");
    return $self->{'data_cache'}{'trace'}{'count'}++;
}

sub log_and_say_if_verbose {
    my ( $self, $log, $args_hr ) = @_;
    return if $ENV{'TAP_COMPLIANT'};
    local $args_hr->{'do_not_add_stamp'} = $args_hr->{'do_not_add_stamp'};
    $log = $self->_add_stamp( $log, [ caller(1) ] ) if !$args_hr->{'do_not_add_stamp'};
    $self->log( $log, $args_hr );
    $args_hr->{'do_not_add_stamp'} = 1;
    chomp $log;
    print "$log\n" if $self->{'global_share'}{'objects'}{'param_obj'}->param('verbose');
    return;
}

sub log_and_say {
    my ( $self, $log, $args_hr ) = @_;
    return if $ENV{'TAP_COMPLIANT'};
    local $args_hr->{'do_not_add_stamp'} = $args_hr->{'do_not_add_stamp'};
    $log = $self->_add_stamp( $log, [ caller(1) ] ) if !$args_hr->{'do_not_add_stamp'};
    $self->log( $log, $args_hr );
    $args_hr->{'do_not_add_stamp'} = 1;
    chomp $log;
    print "$log\n";
    return;
}

sub log {
    my ( $self, $log, $args_hr ) = @_;
    $log = $self->_add_stamp( $log, [ caller(1) ] ) if !$args_hr->{'do_not_add_stamp'};

    if ( !$self->{'log_fh'} || !fileno( $self->{'log_fh'} ) ) {
        $self->debug('initializing /var/log/chkservd.log file handle') unless $args_hr->{'no_fh_debug'};

        close $self->{'log_fh'} if defined $self->{'log_fh'};    # just to make sure
        delete $self->{'log_fh'};                                # just to make sure
        my $old_umask = umask(0077);                             # Case 92381: Logs should not be world-readable.

        if ( open $self->{'log_fh'}, '>>', $self->{'log_file'} ) {
            Cpanel::Sys::Chattr::set_attribute( $self->{'log_fh'}, 'APPEND' );
            $self->info("Opened $self->{'log_file'} in append mode");
            $self->attach_output_to_log() if $self->{'is_daemonized'};    # and it matches $$ ?
            umask($old_umask);
        }
        else {
            $self->panic("Failed to open $self->{'log_file'} in append mode: $!\n$log");    # make sure $log gets logged *somewhere*
            umask($old_umask);
            return;
        }
    }
    else {
        $self->debug("reusing $self->{'log_file'} file handle") unless $args_hr->{'no_fh_debug'};
    }

    $log .= "\n" if !$args_hr->{'do_not_add_newline'} && $log !~ m{\n$};
    syswrite( $self->{'log_fh'}, $log );    #do not buffer

    return 1;
}

sub attach_output_to_log {
    my ($self) = @_;

    if ( !fileno( $self->{'log_fh'} ) ) { return; }

    close STDERR;
    $self->debug('Attaching STDERR to log') if $self->{'debug'};
    open( STDERR, '>>&=', $self->{'log_fh'} ) or $self->error("Could not attach STDERR: $!");

    # close STDOUT; # this close will silently keep the open()s from working
    #    if we do ever see a need for this to be closed then it must be done this way: Cpanel::POSIX::Tiny::close(fileno(STDOUT));
    $self->debug('Attaching STDOUT to log') if $self->{'debug'};
    open( STDOUT, '>>&=', $self->{'log_fh'} ) or $self->error("Could not attach STDOUT: $!");

    $_->autoflush(1) for ( \*STDOUT, \*STDERR );

    $self->debug('Attaching STD* log complete') if $self->{'debug'};

    return;
}

sub remove_chksrvd_disable_files {
    my ( $self, $service ) = @_;

    for my $file ( '/etc/' . $service . 'isevil', '/etc/' . $service . 'disable' ) {
        if ( -e $file ) {
            unlink $file or return;
        }
    }

    return 1;
}

sub has_chkservd_disable_file {
    my ( $self, $service ) = @_;
    return 1 if -e '/etc/' . $service . 'isevil' || -e '/etc/' . $service . 'disable';
    return;
}

sub update_cpconf {
    my ( $self, $update_hr ) = @_;
    $self->init_global_share();    # freshen cache if needed

    require Cpanel::Config::CpConfGuard;
    my $cpconf  = Cpanel::Config::CpConfGuard->new();
    my $data_hr = $cpconf->{'data'};
    @$data_hr{ keys %$update_hr } = values %$update_hr;
    return if !$cpconf->save();

    Cpanel::Config::CpConfGuard::clearcache();

    $self->init_global_share();    # freshen cache w/ new stuff

    return 1;
}

sub is_skipped_in_cpconf {
    my ( $self, $service ) = @_;

    return 1
      if exists $self->{'global_share'}{'data_cache'}{'cpconf'}{ 'skip' . $service }
      && $self->{'global_share'}{'data_cache'}{'cpconf'}{ 'skip' . $service };
    return;
}

sub ensure_global_share {
    my ( $self, $force ) = @_;

    # freshen our cache if its "old":
    if ( $force || ( $self->{'global_share'}{'data_cache'}{'cache_time'} + 360 ) < time() ) {
        $self->clear_data_cache();
        $self->init_global_share();
    }
    return;
}

sub _create_data_cache {
    my ($self) = @_;

    %{ $self->{'global_share'}{'data_cache'} } = (
        'cache_time' => time,                                                                                                                                             # these functions are self caching, so we simply rebuild them when this time is "old"
        'cpconf'     => $INC{'Cpanel/Config/LoadCpConf.pm'} ? scalar Cpanel::Config::LoadCpConf::loadcpconf() : scalar Cpanel::Config::LoadCpConf::Micro::loadcpconf(),
        'hostname'   => Cpanel::Hostname::gethostname(),
    );

    if ( !exists $self->{'global_share'}{'objects'} ) {
        $self->{'global_share'}{'objects'} = {};
    }
    return 1;
}

sub init_global_share {
    my ($self) = @_;

    $self->_create_data_cache();
    $self->_load_user_map();
    return;
}

sub _load_user_map {
    my ($self) = @_;

    $self->{'global_share'}{'data_cache'}{'user_domain_map'} = scalar Cpanel::Config::LoadUserDomains::Tiny::loadtrueuserdomains( undef, 1, 0 );
    $self->{'global_share'}{'data_cache'}{'domain_user_map'} = scalar Cpanel::Config::LoadUserDomains::Tiny::loaduserdomains( undef, 1, 0 );

    return;
}

sub tailwatchd_is_disabled {
    my ($self) = @_;
    return 1 if $self->has_chkservd_disable_file('tailwatchd');
    return 1 if $self->is_skipped_in_cpconf('tailwatchd');
    return;
}

sub clear_data_cache {
    %{ shift->{'global_share'}{'data_cache'} } = ();
}

sub register_action_module {
    my $self       = shift;
    my $module_obj = shift;
    my $modname    = shift;
    push @{ $self->{'register_module'} }, [ $modname => $modname->VERSION() || 'no version reported', ];

    $self->setup_max_action_wait_time( $module_obj, $modname );

    push @{ $self->{'ACTIONLIST'} }, { 'obj' => $module_obj };
}

sub setup_max_action_wait_time {
    my ( $self, $module_obj ) = @_;

    if ( $module_obj->{'internal_store'}{'check_interval'} && $module_obj->{'internal_store'}{'check_interval'} < $self->{'MAX_ACTION_WAIT_TIME'} ) {
        $self->{'MAX_ACTION_WAIT_TIME'} = $module_obj->{'internal_store'}{'check_interval'};
    }

    $self->{'MAX_ACTION_WAIT_TIME'};
}

sub register_reload_module {
    my $self       = shift;
    my $module_obj = shift;
    my $modname    = shift;
    push @{ $self->{'register_module'} }, [ $modname => $modname->VERSION() || 'no version reported', ];
    push @{ $self->{'RELOADLIST'} }, { 'obj' => $module_obj };
}

sub register_module {
    my $self       = shift;
    my $module_obj = shift;
    my $modname    = shift;
    my $readpoint  = shift;
    my $logfiles   = shift;

    push @{ $self->{'register_module'} }, [ $modname => $modname->VERSION() || 'no version reported', ];

    foreach my $logfile ( @{$logfiles} ) {
        if ( ref $logfile eq 'CODE' ) {
            push @{ $self->{'LOOKUPLIST'} }, { 'coderef' => $logfile, 'readers' => $readpoint, 'module_obj' => $module_obj };
            next;
        }
        $self->ensure_file_is_in_filelist( $logfile, $readpoint, $module_obj, 0 );
    }

}

sub get_pid_from_pidfile {
    my ($self) = @_;
    if ( -e $self->{'pid_file'} ) {
        open my $oldpid_fh, '<', $self->{'pid_file'}
          or die "Pid file exists but could not be read: $!";
        chomp( my $curpid = <$oldpid_fh> );
        close $oldpid_fh;
        my $pid = int $curpid;
        if ( $pid && kill 'ZERO', $curpid ) {
            require Cpanel::LoadFile;
            for my $file (qw( stat status )) {
                my $text = Cpanel::LoadFile::load_if_exists("/proc/$pid/$file");
                return $pid if index( $text, 'tailwatchd' ) > -1;
            }
        }
    }
    return 0;
}

sub run {
    my ( $self, $quiet, %opts ) = @_;
    $quiet ||= 0;
    $self->sdnotify()->enable() if $opts{'systemd'};

    if ( $self->tailwatchd_is_disabled() ) {
        print "tailwatchd is disabled\n";
        return;
    }

    my $curpid = $self->get_pid_from_pidfile();
    if ( $curpid && $curpid != $$ ) {
        die "$self->{'zero_name'} is already running.";
    }

    my $have_at_least_one_driver = 0;
    for my $driver ( @{ $self->{'enabled_modules'} } ) {
        if ( $driver->[1] ) {
            $have_at_least_one_driver++;
            last;
        }
    }
    if ( !$have_at_least_one_driver ) {
        warn "All drivers are disabled, at least one must be enabled for tailwatchd to do anything useful. See --help for more info\n";
    }

    print "[$self->{'starttime_human'}] Starting $0 daemon\n";
    if ( exists $self->{'data_cache'}{'trace'}{'limit'} ) {
        print "Trace is on and set to '$self->{'data_cache'}{'trace'}{'limit'}'\n" if !$quiet;
        $self->log("Trace is on and set to '$self->{'data_cache'}{'trace'}{'limit'}'\n");
    }

    if ( $self->{'global_share'}{'objects'}{'param_obj'}->param('debug') ) {
        print "Debug is on for drivers to use.\n" if !$quiet;
        $self->log("Debug is on for drivers to use.\n");
    }

    print "Log is at $self->{'log_file'}\n" if !$quiet;

    ## daemonize if not performing a hot-restart and not using systemd ##
    if ( $opts{'resume'} ) {
        print "Resuming from hot restart\n" if !$quiet;
    }
    elsif ( !$self->sdnotify()->is_enabled() ) {
        require Cpanel::Sys::Setsid;
        Cpanel::Sys::Setsid::full_daemonize();
    }

    $self->{'is_daemonized'} = $$;

    $0 = $self->{'zero_name'};

    {
        local $| = 1;
        my $temp_pid_file = $self->{'pid_file'} . '.' . $$;

        if ( defined $pid_fh ) {
            close $pid_fh;
            undef $pid_fh;
        }

        sysopen $pid_fh, $temp_pid_file, Cpanel::Fcntl::or_flags(qw( O_WRONLY O_EXCL O_CREAT )), 0600 or die "failed to create new pid file for tailwatchd: $!";
        print {$pid_fh} $$                            or die "failed to create new pid file for tailwatchd: $!";
        rename( $temp_pid_file, $self->{'pid_file'} ) or die "failed to rename pid file in place";
    }

    Cpanel::Timezones::SubProc::calculate_TZ_env();

    eval {
        #   close STDOUT; # this keeps attach_output_to_log() from being able to do what its name says w/ STDOUT
        #      if we do ever see a need for this to be closed then it must be done this way: Cpanel::POSIX::Tiny::close(fileno(STDOUT));
        Cpanel::Autodie::open( \*STDIN,  '<', '/dev/null' );
        Cpanel::Autodie::open( \*STDOUT, '>', '/dev/null' );
        Cpanel::Autodie::open( \*STDERR, '>', '/dev/null' );

        $self->sdnotify()->ready_and_wait_for_boot_to_finish(
            {
                'waiting_callback' => sub ($msg) {
                    $self->info($msg);
                },
            }
        );

        $self->log("[START] $$ $self->{'starttime'}") or die "Could not initiate log $self->{'log_file'}: $!";

        if ( exists $self->{'data_cache'}{'trace'}{'limit'} ) {
            $self->log("[TRACE] $$ $self->{'starttime'} Trace is on and set to '$self->{'data_cache'}{'trace'}{'limit'}'");
        }

        if ( $self->{'global_share'}{'objects'}{'param_obj'}->param('debug') ) {
            $self->log("[DEBUG] Debug is on for drivers to use.\n");
        }

        $self->attach_output_to_log();
        if ( $self->{'global_share'}{'objects'}{'param_obj'}->param('debug') ) {
            print "  [DEBUG] STDOUT is attached to log file if you see this line in the log\n";
            warn "  [DEBUG] STDERR is attached to log file if you see this line in the log\n";
        }

        $self->openfiles();

        $self->restore_log_positions();

        $self->catch_up();

        while (1) {
            $self->tail_logs();
            sleep(1);
        }
    };

    if ($@) {
        my $err = $@;

        $self->error(
            "tailwatchd error: "

              #We don't know what $err is. First treat it as though it were
              #a Cpanel::Exception object:
              . ( eval { $err->to_string() . $err->longmess } || $err ),
        );
    }

    return;
}

sub ensure_file_is_in_filelist {
    my ( $self, $file, $readpoint, $module_obj, $is_closable ) = @_;
    $is_closable ||= 0;

    my $file_exists = -e $file ? 1 : 0;

    if ( exists $self->{'FILELIST'}->{$file} && !$file_exists ) {
        delete $self->{'FILELIST'}->{$file};    # must've been deleted, if it is recreated it will be readded next run
    }

    return if !$file_exists;                                                       # don't add non existant files
    return if exists $self->{'FILELIST'}{$file}{'drivers'}{ ref($module_obj) };    # don't wipe out what we've already got

    $self->{'FILELIST'}{$file}{'drivers'}{ ref($module_obj) }++;
    $self->{'FILELIST'}{$file}{'is_closable'} = $is_closable;
    push @{ $self->{'FILELIST'}{$file}{'readers'}->{$readpoint} }, { 'obj' => $module_obj };
    push @{ $self->{'FILELIST'}{$file}{'allreaders'} },            { 'obj' => $module_obj };

}

sub process_dynamic_lookup_list {
    my ($self) = @_;
    if ( exists $self->{'LOOKUPLIST'} && ref $self->{'LOOKUPLIST'} eq 'ARRAY' ) {
        for my $hr ( @{ $self->{'LOOKUPLIST'} } ) {
            for my $file ( $hr->{'coderef'}->() ) {
                $self->ensure_file_is_in_filelist( $file, $hr->{'readers'}, $hr->{'module_obj'}, 1 );
            }
        }
    }

    return;
}

sub tail_logs {    ##no critic (ProhibitExcessComplexity) ¯\_(ツ)_/¯
    my $self = shift;
    $self->trace("enter tail_logs()") if $self->{'trace'};

    my $now;
    my $loopcount  = 0;
    my $needs_read = 0;
    my $wait_count = 0;
    my $current_position;
    my ( $inode, $size, $mtime );
    my $all_files_present;
    my %INOTIFY_WANT_LOGS = map { $_ => 1 } keys %{ $self->{'FILELIST'} };    #always catch up first

    local $SIG{'TERM'} = sub {
        $self->{'hasSIG'}     = 1;
        $self->{'hasSIGTERM'} = 1;
    };

    my $skip_waiting = 0;

    while (1) {
        $loopcount++;
        $skip_waiting      = 0;
        $all_files_present = $now = time();

        #use Data::Dumper;
        #print Dumper($self);
        if ( ref $self->{'ACTIONLIST'} ) {
            foreach my $action ( @{ $self->{'ACTIONLIST'} } ) {
                $action->{'obj'}->run( $self, $now );
            }
        }

        $self->process_dynamic_lookup_list();
        my $number_of_open_fds = 0;
        foreach my $logfile ( exists $self->{'inotify'} ? ( keys %INOTIFY_WANT_LOGS ) : ( keys %{ $self->{'FILELIST'} } ) ) {
            $self->debug("looking at $logfile") if $self->{'debug'};
            ( $inode, $size, $mtime ) = ( stat($logfile) )[ 1, 7, 9 ];    #look at what is there now, not open
            if ( !$mtime ) {
                $all_files_present = 0;
                $self->info("$logfile has gone away.  Looking for it to reappear every second.");
                next;
            }
            delete $INOTIFY_WANT_LOGS{$logfile}           if exists $self->{'inotify'};
            $self->debug("checked time/size on $logfile") if $self->{'debug'};
            $number_of_open_fds++;                                        # if this $logfile is not open this moment it will be soon
            $self->debug("$logfile is closeable: $self->{'FILELIST'}{$logfile}{'is_closable'} - Currently open $number_of_open_fds") if $self->{'debug'};
            $needs_read       = $wait_count = 0;
            $current_position = $self->systell( $self->{'FILELIST'}->{$logfile}->{'fh'} );

            # We have to look at the current position with our systell function
            # because tell() will actually be beyond the file for vzfs on virtuozzo
            # due a bug
            if ( defined $size && $size < $current_position ) {    #added defined $size so we
                                                                   #only reopen the log once logrotate is finished to
                                                                   #avoid a race conidtion where the log file stops
                                                                   #getting tailed
                $self->info("$logfile was smaller than the last time we read it (current size:$size, current position: $current_position, previous position:$self->{'POSITIONS'}->{$logfile})!");
                $self->info("Reopening $logfile and starting at the beginning");
                $self->open_log_file($logfile);
                $needs_read = 1;
            }
            elsif ( defined $inode && $inode != $self->{'INODES'}->{$logfile} ) {
                $self->info("$logfile is not the same file as it was last time we looked (previous inode: $self->{'INODES'}->{$logfile}, current inode: $inode)!");
                $self->info("Reopening $logfile and starting at the beginning");
                $self->open_log_file($logfile);
                $needs_read = 1;
            }
            elsif (
                   $mtime > $self->{'MTIMES'}->{$logfile}
                || $self->{'MTIMES'}->{$logfile} > $now
                || ( $mtime == $self->{'MTIMES'}->{$logfile} && $size > $current_position )    # case 50830: If the time is the same as the last check we must look at the size because there may be multiple updates in a second

              ) {                                                                              # now timewarp safe
                $self->{'MTIMES'}->{$logfile} = $mtime;
                $needs_read = 1;
            }
            else {
                $self->debug("$logfile does not need read (size=$size, current_position=$current_position)") if $self->{'debug'};
            }
            if ($needs_read) {
                my $lines_read = 0;
                while ( readline( $self->{'FILELIST'}->{$logfile}->{'fh'} ) ) {
                    foreach my $reader_ref ( @{ $self->{'FILELIST'}->{$logfile}->{'allreaders'} } ) {

                        # $self->trace( ref $reader_ref->{'obj'}, $_ ) if $self->{'trace'};
                        next if ( $reader_ref->{'obj'}->{'process_line_regex'}->{$logfile} && $_ !~ $reader_ref->{'obj'}->{'process_line_regex'}->{$logfile} );

                        #$self->log("Skipping line (process_line_regex $reader_ref->{'obj'}->{'process_line_regex'}->{$logfile}): $_");
                        eval { $reader_ref->{'obj'}->process_line( $_, $self, $logfile, $now ); };
                        $self->error($@) if $@;
                    }

                    # only read $MAX_LINES_TO_PROCESS_ONE_LOOP lines at a time to ensure we
                    # do not allow a single log file that is very
                    # active to tie up tailwatchd
                    if ( ++$lines_read == $MAX_LINES_TO_PROCESS_ONE_LOOP ) {
                        $INOTIFY_WANT_LOGS{$logfile}  = 1 if $self->{'inotify'};    # force read next loop
                        $self->{'MTIMES'}->{$logfile} = 0;                          # force read next loop
                        $skip_waiting                 = 1;
                        last;
                    }
                }
                $self->{'POSITIONS'}->{$logfile} = tell( $self->{'FILELIST'}->{$logfile}->{'fh'} );
                $self->{'POSITIONS_SYNCED'} = 0;
            }

            if ( $self->{'FILELIST'}{$logfile}{'is_closable'} ) {
                $self->debug("$logfile is closable - Currently open $number_of_open_fds") if $self->{'debug'};
                $self->{'max_open_filedescriptors'} ||= 100;    # just in case a driver wipes it out somehow...
                if ( $number_of_open_fds >= $self->{'max_open_filedescriptors'} ) {
                    close $self->{'FILELIST'}->{$logfile}->{'fh'};
                    $number_of_open_fds--;
                    $self->debug("Over fd limit not keeping $logfile open - Currently open $number_of_open_fds") if $self->{'debug'};
                }
            }

        }
        if ( $self->{'hasSIG'} || $self->{'hasSIGTERM'} || $loopcount == 60 ) {
            $self->_handle_signal();
            $loopcount = 0;
        }

        next if $skip_waiting;    # we had too many lines to process in one loop

        if ( exists $self->{'inotify'} && $all_files_present ) {

            my $fd = $self->{'inotify'}->fileno();

            my $seconds_until_next_hour = ( 3600 - ( $now % 3600 ) );
            my $timeout                 = $seconds_until_next_hour < ( $self->{'MAX_ACTION_WAIT_TIME'} + 1 ) ? $seconds_until_next_hour : ( $self->{'MAX_ACTION_WAIT_TIME'} + 1 );    # We always need to do a check at the top of the hour for EximStats

            vec( my $rin, $fd, 1 ) = 1;
            my $fds = select( my $rout = $rin, undef, undef, $timeout );

            if ( $fds > 0 ) {
                foreach my $event ( $self->{'inotify'}->read() ) {
                    my $fullname = $event->fullname();
                    $self->debug("Got inotify event on $fullname") if $self->{'debug'};
                    $INOTIFY_WANT_LOGS{$fullname} = 1;
                }
            }
        }
        else {

            #otherwise we need to sleep and look
            sleep(1);
        }
    }

    return;
}

sub flush_readers {
    my ($self) = @_;

    $self->info("Flushing all readers");

    # Using values because I don't really care about the name of the logfile.
    foreach my $logfile_entry ( values %{ $self->{'FILELIST'} } ) {
        foreach my $reader_ref ( @{ $logfile_entry->{'allreaders'} } ) {
            next unless eval { $reader_ref->{'obj'}->can('flush') };

            $reader_ref->{'obj'}->flush($self);
        }
    }

    return;
}

sub catch_up {
    my $self = shift;

    local $SIG{'TERM'} = sub {
        $self->{'hasSIG'}     = 1;
        $self->{'hasSIGTERM'} = 1;
    };

    $self->trace("catch_up()") if $self->{'trace'};

    $self->process_dynamic_lookup_list();

    foreach my $logfile ( keys %{ $self->{'FILELIST'} } ) {
        next if !-e $logfile;

        # No need to catch up here since at the end of this function
        # we will already be at the previous position and as soon as
        # tail_logs starts it will pickup where it left off
        my $return_position = tell( $self->{'FILELIST'}->{$logfile}->{'fh'} );
        $self->info("Will resume $logfile to $return_position");
        my $new_position = ( $return_position - THIRTYLINESIZE() );
        if ( $new_position > 0 ) {
            $self->info("Reading back thirty lines of $logfile starting at $new_position");
            seek( $self->{'FILELIST'}->{$logfile}->{'fh'}, $new_position, 0 );
            if ( $new_position > THIRTYLINESIZE() ) {
                readline( $self->{'FILELIST'}->{$logfile}->{'fh'} );
            }
        }
        else {
            $self->info("Reading back thirty lines starting at 0 (small file)");
            seek( $self->{'FILELIST'}->{$logfile}->{'fh'}, 0, 0 );
        }
        while ( readline( $self->{'FILELIST'}->{$logfile}->{'fh'} ) ) {
            foreach my $reader_ref ( @{ $self->{'FILELIST'}->{$logfile}->{'readers'}->{ BACK30LINES() } } ) {
                if ( tell( $self->{'FILELIST'}->{$logfile}->{'fh'} ) > $return_position ) { last; }
                $self->trace( ref $reader_ref->{'obj'}, $_ ) if $self->{'trace'};

                next if ( $reader_ref->{'obj'}->{'process_line_regex'}->{$logfile} && $_ !~ $reader_ref->{'obj'}->{'process_line_regex'}->{$logfile} );

                eval { $reader_ref->{'obj'}->process_line( $_, $self, $logfile ); };
                $self->error($@) if $@;
            }
        }
        $self->info("Restoring $logfile to catch up position $return_position");
        seek( $self->{'FILELIST'}->{$logfile}->{'fh'}, $return_position, 0 );
        my $restored_position = tell( $self->{'FILELIST'}->{$logfile}->{'fh'} );
        $self->info("Restored $logfile to position $restored_position");

        if ( $restored_position != $return_position ) {
            $self->error("Failed to restore $logfile to position $return_position.  The log file was unexpected at $restored_position");
        }

        my ( $inode, $mtime ) = ( stat( $self->{'FILELIST'}->{$logfile}->{'fh'} ) )[ 1, 9 ];    # need to look at what we have open

        $self->{'POSITIONS'}->{$logfile} = $return_position;
        $self->{'POSITIONS_SYNCED'}      = 0;
        $self->{'MTIMES'}->{$logfile}    = $mtime;
    }
    $self->save_positions();

    return;
}

sub openfiles {
    my $self = shift;
    $self->process_dynamic_lookup_list();
    foreach my $file ( keys %{ $self->{'FILELIST'} } ) {
        next if !-e $file;
        $self->open_log_file($file);
    }
    return;
}

sub open_log_file {
    my $self = shift;
    my $file = shift;

    if ( exists $self->{'FILELIST'}->{$file}->{'fh'}      && $self->{'FILELIST'}->{$file}->{'fh'}      && ref $self->{'FILELIST'}->{$file}->{'fh'} )      { $self->{'FILELIST'}->{$file}->{'fh'}->close(); }
    if ( exists $self->{'FILELIST'}->{$file}->{'inotify'} && $self->{'FILELIST'}->{$file}->{'inotify'} && ref $self->{'FILELIST'}->{$file}->{'inotify'} ) { $self->{'FILELIST'}->{$file}->{'inotify'}->cancel(); }
    $self->{'FILELIST'}->{$file}->{'fh'} = IO::Handle->new();
    open( $self->{'FILELIST'}->{$file}->{'fh'}, '<', $file );

    my $inode = ( stat( $self->{'FILELIST'}->{$file}->{'fh'} ) )[1];    # look at what we just opened

    $self->{'INODES'}->{$file}    = $inode;
    $self->{'POSITIONS'}->{$file} = 0;
    $self->{'POSITIONS_SYNCED'}   = 0;

    $self->info("$file opened with inode $inode");

    if ( exists $self->{'inotify'} ) {
        if ( !( $self->{'FILELIST'}->{$file}->{'inotify'} = $self->{'inotify'}->watch( $file, Linux::Inotify2::IN_MODIFY() | Linux::Inotify2::IN_DELETE_SELF() | Linux::Inotify2::IN_MOVE_SELF() | Linux::Inotify2::IN_ATTRIB() ) ) ) {    #IN_ATTRIB handles deleted by syslogd
            delete $self->{'inotify'};
            delete $self->{'FILELIST'}->{$file}->{'inotify'};
            $Cpanel::TailWatch::Inotify = 0;
        }
        else {
            $Cpanel::TailWatch::Inotify = 1;
        }
    }
    $self->{'FILELIST'}->{$file}->{'fh'}->blocking(0);
    return;
}

sub restore_log_positions {
    my $self = shift;
    $self->{'POSITIONS'} = {};
    $self->{'MTIMES'}    = {};

    $self->load_positions();

    $self->process_dynamic_lookup_list();
    foreach my $file ( keys %{ $self->{'FILELIST'} } ) {
        next if !$self->{'FILELIST'}->{$file}->{'fh'};
        my ( $size, $mtime ) = ( stat( $self->{'FILELIST'}->{$file}->{'fh'} ) )[ 7, 9 ];    # look at what we are about to seek in
        $self->{'MTIMES'}->{$file} = $mtime;
        my $previous_position = $self->{'POSITIONS'}->{$file};
        my $get_next_line     = 0;
        if ( !$previous_position || $previous_position > $size ) {
            $get_next_line = 1;
            $self->{'POSITIONS'}->{$file} = ( $size - THIRTYLINESIZE() );
            if ( $self->{'POSITIONS'}->{$file} < 0 ) { $self->{'POSITIONS'}->{$file} = 0; $get_next_line = 0; }
        }
        seek( $self->{'FILELIST'}->{$file}->{'fh'}, $self->{'POSITIONS'}->{$file}, 0 );

        my $now_position = tell( $self->{'FILELIST'}->{$file}->{'fh'} );
        $self->info("Restored $file (size:$size) to $now_position (requested $self->{'POSITIONS'}->{$file})");

        if ( $get_next_line && $self->{'POSITIONS'}->{$file} > THIRTYLINESIZE() ) {
            readline( $self->{'FILELIST'}->{$file}->{'fh'} );
        }

    }

    $self->save_positions();
    return;
}

sub load_positions {
    my ($self) = @_;

    # Try to recover from an unrenamed tailwatch positions file
    if (   -e '/var/cpanel/.tailwatch.positions'
        && ( stat(_) )[9] > ( ( stat('/var/cpanel/tailwatch.positions') )[9] || 0 )
        && $self->_read_positions_file('/var/cpanel/.tailwatch.positions') ) {

        # If there was a . in the file we know that it was written completely, but was not
        # link()ed place

        return;
    }

    # Either the temp write file was not there or it did not pass the consitancy check (has a . at the end)
    # So we read the best complete database we have
    $self->_read_positions_file('/var/cpanel/tailwatch.positions');
    return;
}

sub _read_positions_file {
    my ( $self, $file ) = @_;

    $self->ensure_positions_file();    #we cannot read it if it does not exist yet

    if ( open( my $tail_positions_fh, '<', $file ) ) {
        my ( $pfile, $position );
        while ( readline($tail_positions_fh) ) {
            chomp();
            if ( $_ eq '.' ) {    #we know the write was complete because we saw the dot
                                  #if we are reading the .tailwatch.positions file we know
                                  #that the data is newer, but the process died before the link
                                  #could happen.
                close($tail_positions_fh);
                return 1;         #positions read and consistancy check passed
            }

            ( $pfile, $position ) = split( /=/, $_ );

            $self->{'POSITIONS'}->{$pfile} = $position;
        }
        close($tail_positions_fh);
    }
    return 0;    #consistancy check failed
}

sub ensure_positions_file {
    my ($self) = @_;

    if ( !-e '/var/cpanel/tailwatch.positions' ) {
        $self->{'POSITIONS_SYNCED'} = 0;
        open( my $tail_positions_fh, '>>', '/var/cpanel/tailwatch.positions' );
        close($tail_positions_fh);
    }
}

sub save_positions {
    my ($self) = @_;

    $self->ensure_positions_file();    #we cannot read it if it does not exist yet

    return if $self->{'POSITIONS_SYNCED'};    #only write the file if we need to

    # this is no longer any reason to lock the file as we are using a rename to put the file in place and we can never have
    # a half written one
    if ( open( my $tmp_tail_positions_fh, '>', '/var/cpanel/.tailwatch.positions' ) ) {
        $self->{'POSITIONS_SYNCED'} = 1;
        foreach my $file ( keys %{ $self->{'POSITIONS'} } ) {
            print {$tmp_tail_positions_fh} $file . '=' . $self->{'POSITIONS'}->{$file} . "\n";
        }
        print {$tmp_tail_positions_fh} ".\n";    #write a dot at the end of the file so we know we have a good file
        close($tmp_tail_positions_fh);
        rename( '/var/cpanel/.tailwatch.positions', '/var/cpanel/tailwatch.positions' );    # rename is atomic and will overwrite the old file
    }
}

sub THIRTYLINESIZE {
    return ( 8192 * 2 );
}

sub BACK30LINES {
    return 0;
}

sub PREVPNT {
    return 1;
}

sub systell {
    my ( $self, $fh ) = @_;
    return sysseek( $fh, 0, 1 );
}

sub datetime {
    my $self = shift;
    goto &Cpanel::Time::Local::localtime2timestamp;
}

sub _add_stamp {
    my ( $self, $log, $caller_ar ) = @_;
    return '[' . $$ . '] [' . $self->datetime() . "] [$caller_ar->[0]] $log";
}

sub panic {
    my ( $self, $msg ) = @_;
    require Cpanel::Logger;
    $logger ||= Cpanel::Logger->new();
    $logger->warn($msg);
}

sub error {
    my ( $self, $msg ) = @_;
    $self->log( $msg ? "[ERR] $msg" : $msg );
    return;
}

sub info {
    my ( $self, $msg ) = @_;
    $self->log( $msg ? "[INFO] $msg" : $msg );
    return;
}

sub debug {
    my ( $self, $msg ) = @_;
    return if !$self->{'debug'};
    $msg = $self->_add_stamp( $msg, [ caller(1) ] ) . ' [DEBUG]';
    $self->log( $msg, { 'do_not_add_stamp' => 1, 'no_fh_debug' => 1, } );
}

sub has_sql_file {
    my ( $self, $ns ) = @_;
    return if !$ns;
    my ($service) = reverse( split( /::/, lc($ns) ) );    #lc safe here as ns will never be utf8
    return "/var/cpanel/sql/$service.sql" if -s "/var/cpanel/sql/$service.sql";
    return;
}

sub log_sql {
    my ( $self, $sql, $args_hr ) = @_;
    $args_hr->{'no_fh_debug'} ||= 0;

    my ($service)     = reverse( split( /::/, lc( ( caller(0) )[0] ) ) );    #lc safe here as caller will never be utf8
    my $fh_cache_name = 'sql_log_fh_' . $service;
    my $sql_file      = "/var/cpanel/sql/$service.sql";

    if ( !-d '/var/cpanel/sql/' ) {
        require Cpanel::SafeDir::MK;                           # don't add to memory unless we have to
        Cpanel::SafeDir::MK::safemkdir('/var/cpanel/sql/');    # if it fails then its already logged and it will go to log() when the file can't be opened
    }
    $sql =~ s{[\n\r]+}{}g;
    $sql .= ';' if $sql !~ m{\;$}g;
    $sql .= "\n";

    if ( !$self->{$fh_cache_name} || !fileno( $self->{$fh_cache_name} ) ) {
        $self->debug("initializing $sql_file file handle") unless $args_hr->{'no_fh_debug'};

        # we cannot close a FH when not previously opened with perl522
        if ( $self->{$fh_cache_name} && fileno( $self->{$fh_cache_name} ) ) {
            close $self->{$fh_cache_name};    # just to make sure
        }
        delete $self->{$fh_cache_name};       # just to make sure
        if ( sysopen $self->{$fh_cache_name}, $sql_file, Cpanel::Fcntl::or_flags(qw( O_WRONLY O_APPEND O_CREAT )), 0600 ) {
            chmod( 0600, $self->{$fh_cache_name} );
            $self->info("Opened $sql_file in append mode");
        }
        else {
            $self->panic("Failed to open $sql_file in append mode: $!\n$sql");    # make sure $sql gets logged *somewhere*
            return;
        }
    }
    else {
        $self->debug("reusing $sql_file file handle") unless $args_hr->{'no_fh_debug'};
    }

    syswrite( $self->{$fh_cache_name}, $sql );    #do not buffer
}

sub _is_loopback {
    my $self = shift;

    goto \&Cpanel::IP::Loopback::is_loopback;
}

sub _load_module {
    my $self = shift;
    my $mod  = shift;
    my $opts = shift;
    my $file = $mod . '.pm';
    my $ns   = 'Cpanel::TailWatch::' . $mod;
    my $req  = 'Cpanel/TailWatch/' . $file;

    if ( exists $INC{$req} ) {
        return $ns;    #already loaded
    }

    if ( eval q{require $req} ) {
        my $obj;
        if ( my $cr = $ns->can('is_enabled') ) {
            my $on = $cr->( $ns, $self ) || 0;
            push @{ $self->{'enabled_modules'} }, [ $ns, $on ];

            if ($on) {
                eval { $ns->can('init') && $ns->init($self) };
                if ($@) { $self->alert( "The tailwatchd driver '$ns' ($req) could not be initiated.", $@ ); }
                if ( ref $opts eq 'ARRAY' && scalar @$opts ) {
                    eval { $obj = $ns->new( $self, @$opts ) };
                }
                else {
                    eval { $obj = $ns->new($self) };
                }
                if ($@) { $self->alert( "The tailwatchd driver '$ns' ($req) could not create an object.", $@ ); }
            }
            else {
                $self->log("The tailwatchd driver '$ns' is not enabled.");
            }
        }
        return ( 1, $ns, $file, $req, $obj );
    }
    else {
        $self->error("Failed to load $mod: $@");
    }
    return ( 0, $ns, $file, $req, undef );
}

sub _handle_signal {
    my $self = shift;

    $self->save_positions();

    if ( $self->{'hasSIGTERM'} ) {    #we set hasSIG and hasSIGTERM
        $self->sdnotify()->stopping();
        $self->log_and_say("tailwatch exiting on SIGTERM\n");
        exit;                         ## no critic(Cpanel::NoExitsFromSubroutines) -- desired behavior
    }
    elsif ( $self->{'hasSIGUSR1'} ) {

        alarm(0);

        # Prevent accidental signals from killing us until the new version takes over.
        $SIG{'ALRM'} = $SIG{'HUP'} = $SIG{'USR1'} = 'IGNORE';    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
        $self->sdnotify()->reloading();
        delete $self->{'inotify'};
        require Cpanel::PsParser;
        my $thispid = $$;
        if ( my @child_pids_to_kill = grep { $_ != $thispid } Cpanel::PsParser::get_child_pids($thispid) ) {
            require Cpanel::Kill;
            Cpanel::Kill::safekill_multipid( \@child_pids_to_kill, 0, 1 );
        }
        exec '/usr/local/cpanel/libexec/tailwatch/tailwatchd', '--resume', $self->sdnotify()->is_enabled() ? '--systemd' : ();
    }
    elsif ( $self->{'hasSIG'} ) {
        $self->sdnotify()->reloading();
        Cpanel::Timezones::SubProc::calculate_TZ_env();
        $self->info("tailwatch saving positions and reloading configuration on SIG\n");
        $self->{'MAX_ACTION_WAIT_TIME'} = 2000;    #time before inotify timeout (will be adjusted down by modules we load)
        $self->ensure_global_share(1);
        if ( ref $self->{'RELOADLIST'} ) {
            foreach my $action ( @{ $self->{'RELOADLIST'} } ) {
                $action->{'obj'}->reload( $self, time() );
            }
        }
        $self->flush_readers();
        $self->sdnotify()->ready();
    }
    $self->{'hasSIG'} = 0;

    return 1;
}

sub sdnotify {
    my ($self) = @_;
    return Cpanel::Systemd::Notify::Boot->get_instance( 'service' => 'tailwatchd' );
}

#for unit test mocking
sub tail_watch_driver_dir {
    return '/usr/local/cpanel/Cpanel/TailWatch';
}

1;

__END__

=head1 NAME

Cpanel::TailWatch

=head1 DESCRIPTION

Application wrapper module around various service drivers.

=head1 Drivers

=over 4

=item * Should not print or warn/carp/die/croak

=item * Should instead use log() to communicate information

    $tail_obj->debug($msg); # gets logged if in debug mode

By default the log entry will be preceded by
   YYYY-MM-DD HH:MM::SS [calling::package] $msg

And have a newline appended if need be.

You can control this behavior by specifying a hashref as the second arg. The keys are as follows:

=over 4

=item * do_not_add_newline

Do not append a newline to message, use it as is.

=item * do_not_add_stamp

Do not prepend 'YYYY-MM-DD HH:MM::SS [calling::package] ' to message

=back

=item * Should use the main tailobj's data when possible

The main 2 keys in $tail_obj->{'global_share'} are 'objects' and 'data_cache'

=item * Should use their own 'internal_store' hashref to cache data

=item * Should refresh 'internal_store' cache every so often

=item * Should mimick the example module below, including module use and $VERSION

=item * Driver specific helper methods should begin with an underscore

=back

More POD coming soon depending on demand and time.

=head1 Sample Driver

    package Cpanel::TailWatch::Whatever;

    #############################################################
    # no other use()s, require() only *and* only then in init() #
    #############################################################

    # /usr/local/cpanel already in @INC
    # should work with these on but disabled in production for slight memory gain
    # use strict;
    # use warnings;
    # use vars ($VERSION);
    #
    use base 'Cpanel::TailWatch::Base';
    our $VERSION = 0.1;

    #############################################################
    # no other use()s, require() only *and* only then in init() #
    #############################################################

    # Optional
    sub init {
        my ($my_ns, $tailwatch_obj) = @_;

        # this is where modules should be require()'d
        # this method gets called if PKG->is_enabled()
    }

    # Optional
    sub is_enabled {
        my ($my_ns, $tailwatch_obj) = @_;

        # return if !enabled;
        # return 1 if enabled;

        return 1; # its always on
    }

    # Optional
    sub enable {
        my ($tailwatch_obj, $my_ns) = @_;
        # respect verbose flag
        # return 1 if enabled successfully;
        # return; # if enable failed

        # Document once driver's have it
    }

    # Optional
    sub disable {
        my ($tailwatch_obj, $my_ns) = @_;
        # respect verbose flag
        # return 1 if disabled successfully;
        # return; # if disable failed

        # Document once driver's have it
    }

    # Required
    sub new {
        my ($my_ns, $tailwatch_obj) = @_;
        my $self = bless { 'internal_store' => {} }, $my_ns;

        $self->{'internal_store'}{'important_path'} = '/usr/local/important';
        if ( !-e $self->{'internal_store'}{'important_path'} ) {
            mkdir $self->{'internal_store'}{'important_path'}, 0755;
        }

        $self->_check_important_data();

        # filelist can include file paths or coderefs that return lists of filepaths
        $tailwatch_obj->register_module( $self, __PACKAGE__, &Cpanel::TailWatch::PREVPNT, ['/var/log/important'] );

        return $self;
    }

    sub process_line {
        my ( $self, $line, $tailwatch_obj, $filename_that_line_is_from ) = @_;

        # do whatever you need to with $line
    }

    ## Driver specific helpers ##

    sub _check_important_data {
        my ($self) = @_;
        my $mtime = int( ( stat('/etc/important_file') )[9] );
        if ( ($self->{'internal_store'}{'important_data_cache_time'} + 1800) < $mtime) {
            $self->_load_important_data();
        }
    }

    sub _load_important_data {
        my ($self) = @_;
        $self->{'internal_store'}{'important_data_cache_time'} = time;
        $self->{'internal_store'}{'important_data'}            = {};

        if (-e '/etc/important_file') {
            if ( open my $fh, '<', '/etc/important_file' ) {
                while( my $line = readline($fh) ) {
                    chomp $line;
                    my ( $key, $value ) = split( /:\s+/, $line );
                    next if $key eq 'not_important';
                    $self->{'internal_store'}{'important_data'}{$key} = $value;
                }
                close $fh
            }
        }
    }

=head2 Using MySQL for Logging and Handling Failure

If a driver uses SQL it should verify queries worked and if they failed use tailwatch's C<log_sql>
function to log the INSERTS to C</var/cpanel/sql/$name.sql> for the duration of the database
outage.

=head3 Log Recovery

Recovering the logged SQL from C</var/cpanel/sql/$name.sql> and inserting it into the proper
database can be automated whenever the $name service is restarted (e.g., running restartsrv_$name).

If that $file exists and the driver has implemented the C<import_sql_file> method exists, the
the name of the C<$file> will be passed to this method for processing. If the method is
not implemented, a helpful message is displayed in the service's error log.

=head3 Database Name

The database name should be the same same as C<$name>.

If that is not the case with this particular driver simply give it a method called C<get_database_name>.

Since object creation may have failed at this point this method should be able to take
the object or the name space as its first argument (IE 'Class method' syntax)

If C<$name> is not correct and this method can not determine the database name (e.g. maybe it's configurable
and available in the object but we only have the name space) then it should return false and the generic
and obvious C<DATABASE_NAME_HERE> will be used instead.

=head1 LICENSE AND COPYRIGHT

   Copyright 2022 cPanel, L.L.C.
