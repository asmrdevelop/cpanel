package Cpanel::ChangePasswd;

# cpanel - Cpanel/ChangePasswd.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::LoadModule            ();
use Cpanel::Locale                ();
use Cpanel::PasswdStrength::Check ();
use Cpanel::PwCache               ();
use Cpanel::SafeRun::Simple       ();
use Cpanel::Services::Enabled     ();
use Cpanel::AcctUtils::Suspended  ();

use Try::Tiny;

my $locale;

{
    my $init;    # just use a simple flag, no need to overwrite _init function
                 #   as this is called at run time

    sub _init {
        return if $init;

        # Changing a password is not a frequent operation
        # cpanel.pl is still using change_password for deprecated API1 call
        # only load main modules when required

        # use multiple lines for PPI parsing purpose
        Cpanel::LoadModule::load_perl_module('Cpanel::AcctUtils::Domain');
        Cpanel::LoadModule::load_perl_module('Cpanel::AdminBin');
        Cpanel::LoadModule::load_perl_module('Cpanel::Auth::Digest::DB::Manage');
        Cpanel::LoadModule::load_perl_module('Cpanel::Auth::Digest::Realm');
        Cpanel::LoadModule::load_perl_module('Cpanel::Auth::Generate');
        Cpanel::LoadModule::load_perl_module('Cpanel::Auth::Shadow');
        Cpanel::LoadModule::load_perl_module('Cpanel::Dovecot::Utils');
        Cpanel::LoadModule::load_perl_module('Cpanel::Hooks');

        # logger is not required
        require Cpanel::NSCD;
        require Cpanel::SSSD;
        require Cpanel::Session::SinglePurge;
        require Cpanel::Wrap;
        require Cpanel::Wrap::Config;

        $init = 1;

        return;
    }
}

sub change_password {
    my %OPTS              = @_;
    my $current_password  = $OPTS{'current_password'};
    my $new_password      = $OPTS{'new_password'};
    my $optional_services = $OPTS{'optional_services'};
    my $ip                = $OPTS{'ip'};
    my $origin            = $OPTS{'origin'};
    my $initiator         = $OPTS{'initiator'};
    $locale ||= Cpanel::Locale->get_handle();

    my ( $system_user, $session_user );

    if ( $ENV{'TEAM_USER'} && $ENV{'TEAM_OWNER'} ) {
        $system_user  = $ENV{'TEAM_OWNER'};
        $session_user = $OPTS{'user'};
    }
    else {
        $system_user = $session_user = $OPTS{'user'};
    }

    _init();

    my ( $status, $msg ) = _validate_change_password_input(
        'user'              => $session_user,
        'new_password'      => $new_password,
        'current_password'  => $current_password,
        'locale'            => $locale,
        'optional_services' => $optional_services,
        'system_user'       => $system_user,
    );
    return ( $status, $msg ) if !$status;

    # TODO: Check if the team_user is suspended DUCK-6304
    if ( Cpanel::AcctUtils::Suspended::is_suspended($system_user) ) {
        return ( 0, $locale->maketext( 'Sorry, the user “[_1]” is currently suspended. Changing the user’s password would unsuspend the account.', $system_user ) );
    }

    my @CLIST;
    my $app = 'passwd';

    my $check_method = $OPTS{'password_strength_check'} || q<>;
    if ( $check_method ne 'none' && !Cpanel::PasswdStrength::Check::check_password_strength( 'pw' => $new_password, 'app' => $app ) ) {
        my $required_strength = Cpanel::PasswdStrength::Check::get_required_strength($app);
        return ( 0, $locale->maketext( 'Sorry, the password you selected cannot be used because it is too weak and would be too easy to guess. Please select a password with strength rating of [numf,_1] or higher.', $required_strength ) );
    }

    if ( $> == 0 ) {
        require Cpanel::Services::Cpsrvd;

        my %change_data = (
            'user'              => $session_user,
            'newpass'           => $new_password,
            'new_password'      => $new_password,
            'current_password'  => $current_password,
            'optional_services' => $optional_services,
            'message'           => $locale->maketext( 'Password changed for user “[_1]”.', $session_user ),
            'applist'           => \@CLIST,
            'origin'            => $origin,
            'initiator'         => $initiator,
            ( $ip ? ( 'ip' => $ip ) : () ),
        );

        my $hook_info = {
            'category'      => 'Passwd',
            'event'         => 'ChangePasswd',
            'stage'         => 'pre',
            'escalateprivs' => 1,
            'blocking'      => 1,
        };

        my ( $hook_res, $hook_msgs ) = Cpanel::Hooks::hook(
            $hook_info,
            \%change_data,
        );
        return ( 0, Cpanel::Hooks::hook_halted_msg( $hook_info, $hook_msgs ) ) if !$hook_res;

        my ( $status, $rawout, $old_crypted_pw );
        if ( $ENV{'TEAM_USER'} ) {
            ( $status, $rawout, $old_crypted_pw ) = change_team_user_password( $session_user, $new_password );
        }
        else {
            ( $status, $rawout, $old_crypted_pw ) = change_cPanel_user_password( $system_user, $new_password );
        }
        if ( !$status ) {
            return ( $status, $rawout, $rawout );
        }

        $change_data{'rawout'} = $rawout;

        push( @CLIST, { 'app' => 'system' } );

        # SECURITY: MYSQL ROOT SHOULD NOT CHANGE IT SHOULD BE DIFFERENT THAN THE ROOT PASS
        # TEAM_USER Does not require the password to be propogated.
        if ( $system_user ne 'root' && !$ENV{'TEAM_USER'} ) {

            # Remote propagation should ideally be at the end of the other
            # changes, but as of now we lack rollback logic for the other
            # changes like FTP and SQL. Putting the remote propagation here,
            # after the local system user update achieves a compromise:
            # do the local update first so that any failures short-circuit
            # the whole process, then propagate immediately after so that
            # we can roll back the changes if the remote update fails.
            #
            my ( $propagate_ok, $propagate_err ) = _propagate_pw_change(
                username          => $system_user,
                new_password      => $new_password,
                old_crypted_pw    => $old_crypted_pw,
                optional_services => $optional_services,
            );
            return ( 0, $propagate_err ) if !$propagate_ok;

            require Cpanel::ServerTasks;
            my $ret = Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 10, "ftpupdate" );
            if ($ret) {
                $rawout .= $locale->maketext("[output,abbr,FTP,File Transfer Protocol] password change has been queued.");
            }
            else {
                $rawout .= $locale->maketext("[output,abbr,FTP,File Transfer Protocol] password change could not be queued.");
            }
            $rawout .= "\n";
            push( @CLIST, { 'app' => 'ftp' } );

            push( @CLIST, { 'app' => 'mail' } );
            my $uid = ( Cpanel::PwCache::getpwnam($system_user) )[2];

            my ( $db_out, @db_clist ) = _changepasswd_dbs( $optional_services, $new_password, $uid );
            $rawout .= $db_out;
            push @CLIST, @db_clist;

            if ( $optional_services->{'digest'} ) {
                push( @CLIST, { 'app' => 'webdisk (digest)' } );
            }
        }
        _notify_password_change_if_enabled( \%change_data );

        Cpanel::Services::Cpsrvd::signal_users_cpsrvd_to_reload($system_user);

        # NOTIFY PASSWORD CHANGE HERE IF NEEDED

        Cpanel::Hooks::hook(
            {
                'category'      => 'Passwd',
                'event'         => 'ChangePasswd',
                'stage'         => 'post',
                'escalateprivs' => 1,
            },
            \%change_data,
        );
        _run_hooked_modules(%change_data);
        Cpanel::NSCD::clear_cache();
        Cpanel::SSSD::clear_cache();

        # TODO: DUCK-6290
        Cpanel::Dovecot::Utils::flush_auth_caches($system_user);
        Cpanel::Session::SinglePurge::purge_user( $session_user, 'password_change' );

        return ( 1, $locale->maketext( 'Password changed for user “[_1]”.', $session_user ), $rawout, \@CLIST );
    }

    require Cpanel::Wrap;
    require Cpanel::Wrap::Config;
    if ( !$current_password ) {
        return ( 0, $locale->maketext( 'You did not pass the “[output,strong,_1]” parameter in your request.', 'current_password' ) );
    }
    my $result = Cpanel::Wrap::send_cpwrapd_request(
        'namespace' => 'Cpanel',
        'module'    => 'security',
        'function'  => 'CHANGE',
        'data'      => \%OPTS,
        'env'       => Cpanel::Wrap::Config::safe_hashref_of_allowed_env(),
    );

    if ( $result->{'status'} && ref $result->{'data'} ) {
        return ( $result->{'data'}->{'status'}, $result->{'data'}->{'statusmsg'}, $result->{'data'}->{'rawout'}, $result->{'data'}->{'services'} );
    }

    return ( $result->{'status'}, $result->{'statusmsg'} );
}

sub _validate_change_password_input {
    my %args = @_;
    my ( $user, $new_password, $current_password, $locale, $optional_services, $system_user ) = delete @args{qw/user new_password current_password locale optional_services system_user/};
    die 'Unexpected arguments given to _validate_change_password_input()' if %args;

    # If optional services is not passed, we use the current settings
    # TODO: Create a Webdisk account for team_user DUCK-6712
    if ( !$ENV{'TEAM_USER'} && ( !$optional_services || !exists $optional_services->{'digest'} ) ) {
        $optional_services->{'digest'} = get_digest_auth_option( {}, $system_user );
    }

    if ( !$user ) {
        return ( 0, $locale->maketext( 'You did not pass the “[output,strong,_1]” parameter in your request.', 'user' ) );
    }
    if ( !$new_password ) {
        return ( 0, $locale->maketext( 'You did not pass the “[output,strong,_1]” parameter in your request.', 'new_password' ) );
    }

    if ( $new_password =~ /\Q${user}\E/i ) {
        return ( 0, $locale->maketext('Sorry, the password may not contain the username for security reasons.') );
    }
    if ( $current_password and $new_password eq $current_password ) {
        return ( 0, $locale->maketext('You cannot reuse the old password.') );
    }
    if ( length($new_password) < 5 ) {
        return ( 0, $locale->maketext('Sorry, passwords must be at least 5 characters for security reasons.') );
    }
    if ( !$ENV{'TEAM_USER'} && !( Cpanel::PwCache::getpwnam($system_user) )[0] ) {
        return ( 0, $locale->maketext( 'Sorry, the user “[_1]” does not exist.', $system_user ) );
    }

    return ( 1, '_validate_change_password_input - validation passes' );
}

sub _propagate_pw_change (%opts) {
    require Cpanel::LinkedNode::Worker::WHM;
    require Cpanel::OrDie;

    my ( $username, $new_password, $old_crypted_pw, $optional_services ) = @opts{
        'username',
        'new_password',
        'old_crypted_pw',
        'optional_services',
    };

    return Cpanel::OrDie::convert_die_to_multi_return(
        sub {
            Cpanel::LinkedNode::Worker::WHM::do_on_all_user_nodes(
                username => $username,

                local_undo => sub {
                    if ($old_crypted_pw) {
                        require Cpanel::Auth::Shadow;
                        my ( $status, $statusmsg ) = Cpanel::Auth::Shadow::update_shadow( $username, $old_crypted_pw );
                        warn "Local shadow undo: $statusmsg\n" if !$status;
                    }
                    else {
                        warn "No old crypted pw to restore! Local password remains changed.\n";
                    }
                },

                remote_action => sub ($worker_conf) {
                    my $api = $worker_conf->get_remote_api();

                    $api->request_whmapi1_or_die(
                        'passwd',
                        {
                            user           => $username,
                            password       => $new_password,
                            db_pass_update => $optional_services->{'mysql'} || $optional_services->{'postgres'},
                            enabledigest   => $optional_services->{'digest'},
                        },
                    );
                },
            );
        },
    );
}

# NB: tested directly
#
# TODO: It would be ideal to separate all of the password-change
# pieces into functions and use something like Cpanel::CommandQueue
# to achieve at least basic exception safety for password changes.
sub _changepasswd_dbs {
    my ( $optional_services, $new_password, $uid ) = @_;

    my @CLIST;

    my $rawout = q<>;

    ## MYSQL
    if ( $optional_services->{'mysql'} && Cpanel::Services::Enabled::is_provided('mysql') ) {
        local $ENV{'REMOTE_PASSWORD'} = $new_password;    #TEMP_SESSION_SAFE
        $rawout .= Cpanel::SafeRun::Simple::saferun( '/usr/local/cpanel/bin/cpmysqladmin', $uid, 'UPDATEDBOWNER' );
        push( @CLIST, { 'app' => 'MySQL' } );
    }

    # For some reason we always update PgSQL, even if it’s not given
    # in $optional_services.
    if ( Cpanel::Services::Enabled::is_provided('postgresql') ) {
        local $ENV{'REMOTE_PASSWORD'} = $new_password;    #TEMP_SESSION_SAFE
        $rawout .= Cpanel::SafeRun::Simple::saferun( '/usr/local/cpanel/bin/postgresadmin', $uid, 'UPDATEDBOWNER' );
        push( @CLIST, { 'app' => 'postgresql' } );
    }

    return $rawout, @CLIST;
}

sub _run_hooked_modules {    # no need to call _init private function
    my %OPTS = @_;
    my ( $encrypted_pass, $pass_change_time ) = ( Cpanel::PwCache::getpwnam( $OPTS{'user'} ) )[ 1, 10 ];
    require Cpanel::Auth::Digest::Realm;
    require Cpanel::PwFileCache;
    Cpanel::PwFileCache::save_pw_cache(
        {
            'passwd_cache_file' => $OPTS{'user'},
            'passwd_cache_dir'  => '/var/cpanel/@pwcache',
            'keys'              => {
                'encrypted_pass' => $encrypted_pass,
                'quota'          => 0,
                'realm'          => Cpanel::Auth::Digest::Realm::get_realm(),
                'pass'           => $OPTS{'newpass'},
                'homedir'        => Cpanel::PwCache::gethomedir( $OPTS{'user'} ),
                'lastchanged'    => $pass_change_time,
            }
        }
    );

    my $loaded_chpassmods_ref = loadmodules();
    foreach my $module ( keys %{$loaded_chpassmods_ref} ) {
        eval 'Cpanel::ChangePasswd::' . $module . '::process(@_);';
        if ($@) {
            syswrite( STDERR, $@ );
        }
    }

    return;
}

sub _loadmodules_from {
    return '/usr/local/cpanel/Cpanel/ChangePasswd';
}

sub loadmodules {    # no need to call _init, no modules required here
    my %LOADED_CHANGEPASSWD_MODULES;
    opendir( my $mod_dir, _loadmodules_from() );
    while ( my $mod = readdir($mod_dir) ) {
        next if ( $mod !~ /\.pm$/ );
        $mod =~ s/\.pm//g;
        eval 'require Cpanel::ChangePasswd::' . $mod . ';';
        if ( !$@ ) {
            $LOADED_CHANGEPASSWD_MODULES{$mod} = 1;
        }
        else {
            syswrite( STDERR, $@ );
        }

    }
    closedir($mod_dir);
    return \%LOADED_CHANGEPASSWD_MODULES;
}

sub change_cPanel_user_password {
    my ( $user, $newpass ) = @_;

    require Cpanel::Auth::Generate;
    require Cpanel::Auth::Shadow;
    _init();

    my $crypted_password = Cpanel::Auth::Generate::generate_password_hash($newpass);
    my ( $status, $statusmsg, $old_crypted_pw ) = Cpanel::Auth::Shadow::update_shadow( $user, $crypted_password );
    return ( $status, $statusmsg, $old_crypted_pw );
}

##   1. if present and true, enable and change their digest auth password
##   2. if present and false, disable their digest auth password
##   3. if missing and the user is currently enabled with digest auth, do #1 above
##   4. if missing and the user is currently disabled, do #2 above (effectively nothing)
sub get_digest_auth_option {
    my ( $args, $user ) = @_;
    my $digest_auth;

    ## WHM xml-api is starting to favor variables separated by underscore, where
    ##   API2 favors squashing together; there are existing usages of both, and it
    ##   is not worthwhile changing and versioning the APIs
    if ( exists $args->{'digestauth'} || exists $args->{'enabledigest'} ) {
        $digest_auth =
          exists $args->{'digestauth'}
          ? !!$args->{'digestauth'}
          : !!$args->{'enabledigest'};
    }
    else {
        if ( $> == 0 ) {
            require Cpanel::Auth::Digest::DB::Manage;
            $digest_auth = Cpanel::Auth::Digest::DB::Manage::has_entry($user);
        }
        else {
            require Cpanel::AdminBin;
            $digest_auth = Cpanel::AdminBin::adminrun( 'security', 'HASDIGEST', 0 );
        }
    }
    return $digest_auth;
}

sub _notify_password_change_if_enabled {    # no need to call _init private function
    my ($change_data) = @_;

    my $user      = $change_data->{'user'};
    my $initiator = $change_data->{'initiator'};

    if ( $initiator && $initiator ne $user ) { return; }    # Do not notify if root/reseller changes a users password.

    Cpanel::LoadModule::load_perl_module('Cpanel::ContactInfo');
    my $cinfo = Cpanel::ContactInfo::get_contactinfo_for_user($user);
    return if !$cinfo->{'notify_password_change'};

    return _send_password_change_notification($change_data);
}

sub _send_password_change_notification {
    my ($change_data) = @_;

    my $user   = $change_data->{'user'};
    my $cpuser = ( $ENV{'TEAM_USER'} && $user =~ /\@/ ) ? $ENV{'TEAM_OWNER'} : $user;
    my $domain = Cpanel::AcctUtils::Domain::getdomain($cpuser);

    require Cpanel::Notify;
    Cpanel::Notify::notification_class(
        'class'            => 'ChangePassword::User',
        'application'      => 'ChangePassword::User',
        'constructor_args' => [
            username                          => $user,
            to                                => $user,
            user                              => $user,
            user_domain                       => $domain,
            notification_targets_user_account => ( $user ne 'root' ? 1 : 0 ),
            services                          => [ sort( map { $_->{'app'} } @{ $change_data->{'applist'} } ) ],
            origin                            => $change_data->{'origin'},
            source_ip_address                 => $change_data->{'ip'},
            team_account                      => defined $ENV{'TEAM_USER'} ? 1 : 0,
        ]
    );

    return 1;
}

sub change_team_user_password {
    my ( $team_user_with_domain, $new_pass ) = @_;
    $locale ||= Cpanel::Locale->get_handle();

    require Cpanel::Team::Config;

    my $old_crypted_pw = Cpanel::Team::Config::get_team_user($team_user_with_domain)->{password};
    my $team           = Cpanel::Team::Config->new( $ENV{'TEAM_OWNER'} );
    my $team_user      = $ENV{'TEAM_USER'};
    my $status         = $team->set_password( $team_user, $new_pass );
    my $statusmsg      = $locale->maketext( 'Password for “[_1]” has been changed.', $team_user_with_domain );

    return ( $status, $statusmsg, $old_crypted_pw );
}

1;
