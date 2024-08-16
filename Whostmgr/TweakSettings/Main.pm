package Whostmgr::TweakSettings::Main;

# cpanel - Whostmgr/TweakSettings/Main.pm          Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- not warnings safe yet

use Try::Tiny;

use Cpanel::Config::DormantServices        ();
use Cpanel::ConfigFiles::Apache::modules   ();
use Cpanel::ArrayFunc::Uniq                ();
use Cpanel::Config::Constants              ();
use Cpanel::Config::CpConfGuard            ();
use Cpanel::Config::CpConfGuard::Default   ();
use Cpanel::Config::Httpd::EA4             ();
use Cpanel::Config::Services               ();
use Cpanel::ConfigFiles                    ();
use Cpanel::DB::Prefix                     ();
use Cpanel::Debug::Hooks                   ();
use Cpanel::Debug                          ();
use Cpanel::Email::DeferThreshold          ();
use Cpanel::Email::Maildir                 ();
use Cpanel::FileUtils::Write               ();
use Cpanel::Exception                      ();
use Cpanel::Binaries                       ();
use Cpanel::HttpUtils::Version             ();
use Cpanel::Server::Type                   ();
use Cpanel::LoadModule                     ();
use Cpanel::Maxmem                         ();
use Cpanel::Proxy::Tiny                    ();
use Cpanel::Server::Type::Role::SpamFilter ();
use Cpanel::ServerTasks                    ();
use Cpanel::StringFunc::Trim               ();
use Cpanel::Validate::Domain::Tiny         ();
use Cpanel::SSL::DefaultKey::Constants     ();
use Cpanel::OS                             ();

use Whostmgr::Templates::Chrome::Rebuild ();
use Whostmgr::ThemeManager               ();

my $IPv6 = 0;

my $PROXY_SUBDOMAINS_CHANGED_STATE              = 0;
my $PROXY_SUBDOMAINS_AUTODISCOVER_ADD_SCHEDULED = 0;
my $PROXY_SUBDOMAINS_OLD_AUTODISCOVER_HOST;    # we stash the service (formerly proxy) subdomains old host here before it gets changed so we know to match it for add/remove
my $DEFAULT_EMAIL_SEND_LIMITS_DEFER_CUTOFF_PERCENTAGE = 125;

#'Grouping' => {
#        'key' => {
#                'checkval' => sub{return shift;},  # scrub/sanitize; undef means invalid.
#                                                   # NOTE: If the value is valid, the actual value needs to be returned.
#                'default'  => 30,                  # Value when $FORM{'key'} eq ''
#                'help'     => 'Text to display',   # Description
#                'name'     => 'A Friendly Name',   # More friendly name
#                'type'     => 'number'             # Form type
#
#                # Used to ignore processing a submitted item on the backend only.
#                # This is useful when you want to ignore items that are disabled
#                # due to an unresolved dependency, but you don't want to generate
#                # warnings for upon submission.
#
#                # Example: Mail notification thresholds, but mail notifications are disabled.
#
#                'ignoreif' => sub {                # useful for ignoring values that are disabled based on other dependent settings.
#                    return 1 if ( condition );     # Truthy value means this item will NOT be updated on form submission
#                    return 0;                      # Falsy value means this item WILL be updated on submission.
#                },
#
#                # Used to skip displaying an item on the form, and to disable processing it on the backend.
#                'skipif'   => sub {
#                    return 1 if ( condition );     # Truthy value means this item will NOT be shown or updated on submission.
#                    return 0;                      # Falsy value means this item WILL be shown and updated on submission.
#                },
#
#                'action' => sub {                  # return 1 for success 0 for failure
#                    my $val = shift;               # NEW value
#                    my $oldval = shift;            # OLD value
#                    return 1 if ($val eq $oldval);
#                    if ($val) { print "do stuff\n"; return 1;}
#                    else { print "do other stuff\n"; return 1;}
#                },
#
#                'format' => sub { },               # How to present the data in the form
#                                                   # NOTE: return undef means "disabled"
#                'unit' => MB, KB, &, etc.
#        }
#},

sub _format_unlimited {
    return ( !$_[0] || ( $_[0] eq 'unlimited' ) ) ? undef : $_[0];
}

sub _is_natural_number {

    #integers >= 1
    my $val = shift();

    return ( $val && $val =~ m{\A\d+\z} )
      ? int $val
      : ( undef, "Value must be a natural number" );
}

sub _is_positive_float {
    my $val = shift();

    #testing for $val's boolean value rules out the empty string,
    #so the regex can be simpler. Without the boolean test, the regex
    #would have to weed out empty strings.
    return ( $val && $val =~ m{\A \d* (?:\.\d+)? \z}x )
      ? $val + 0    #gets rid of extra 0s
      : ( undef, "Value must be a positive float" );
}

sub _is_float {
    my $val = shift();

    if (   $val ne q{}
        && $val ne q{-}
        && $val =~ m{\A ( -? \d* (?:\.\d+)? ) \z}x ) {
        return $val + 0;    #gets rid of extra 0s
    }
    else {
        return ( undef, "Value must be a float" );
    }
}

# NOTE: This returns 0 if the input is 0. When checking the return from this function
# you should probably check definedness instead of truthiness.
sub _is_whole_number {

    #integers >= 0
    my $val = shift();

    return defined $val && $val =~ m{\A\d+\z}
      ? int $val
      : ( undef, "Value must be a whole number" );
}

sub _is_positive_percentage_float {

    #integers between 0 (exclusive) and 100 (inclusive)
    my $val = shift();

    return defined $val && $val =~ m{\A(\d+\.?\d*)\z} && $1 > 0 && $1 <= 100
      ? sprintf( '%0.4f', $val )
      : ( undef, "Value must be a positive percentage float" );
}

sub _is_positive_percentage_integer {

    #integers between 0 (exclusive) and 100 (inclusive)
    my $val = shift();

    return defined $val && $val =~ m{\A(\d+)\z} && $1 > 0 && $1 <= 100
      ? int $val
      : ( undef, "Value must be a positive percentage integer" );
}

sub _run_in_background {
    my (%opts) = @_;

    return unless $opts{cmd} && ref $opts{cmd} eq 'ARRAY' && scalar @{ $opts{cmd} };

    require Cpanel::Sys::Setsid::Fast;
    require Cpanel::Rlimit;
    require Cpanel::CloseFDs;

    if ( my $pid = fork() ) {
        return 1 if $opts{nowait};
        waitpid( $pid, 0 );
    }
    else {
        Cpanel::Sys::Setsid::Fast::fast_setsid();
        Cpanel::Rlimit::set_rlimit_to_infinity();
        chdir '/';
        Cpanel::CloseFDs::fast_daemonclosefds();
        { exec( @{ $opts{cmd} } ); }
        exit;
    }

    return;
}

our %Conf;

my $_did_init_vars = 0;

sub init {
    _init_vars() if !$_did_init_vars++;
    return;
}

sub _init_vars {    ## no critic qw(ProhibitExcessComplexity)
    my $cpconf_defaults_hr = Cpanel::Config::CpConfGuard::Default::default_statics();

    %Conf = (
        'default_login_theme' => {
            'type'    => 'radio',
            'options' => [ $Whostmgr::ThemeManager::APPS{'login'}{'themelistfunc'}->() ],
            'sorter'  => sub {
                require Cpanel::Sort;
                Cpanel::Sort::list_sort( shift(), { desc => 0 } );
            },
        },
        'numacctlist' => {
            'checkval' => sub {
                my $val = shift();

                if ( $val && $val =~ m{\A\d+\z} ) {
                    return int $val;
                }
                else {
                    return ( undef, 'Value must be a number' );
                }
            },
            'can_undef' => 1,
            'type'      => 'number',

            skipif => \&_solo_license,
        },
        'file_usage' => {
            'type' => 'binary',
        },
        'display_upgrade_opportunities' => {
            'default' => 0,
            'type'    => 'binary',
        },
        'emailpasswords' => {
            'type' => 'binary',
        },
        'use_apache_md5_for_htaccess' => {
            needs_role => 'WebServer',
            'type'     => 'binary',
        },
        'skiphttpauth' => {
            'type' => 'inversebinary',
        },

        'jailapache' => {
            needs_role      => 'WebServer',
            'type'          => 'binary',
            'requires_test' => [ Cpanel::ConfigFiles::Apache::modules::is_supported('mod_ruid2') || '', '==', '1' ],
            'post_action'   => sub {

                #not cpanel.config guard safe
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );

                Cpanel::LoadModule::load_perl_module('Cpanel::Mailman');
                Cpanel::Mailman::setup_jail_flags();

                my $protecthome = 'protecthomecheck ' . ( $val ? 1 : 0 );
                eval { Cpanel::ServerTasks::queue_task( [ 'ApacheTasks', 'TailwatchTasks', 'MysqlTasks' ], 'update_users_jail', 'build_apache_conf', 'apache_restart --force', 'reloadtailwatch', $protecthome ); };
                if ($@) {
                    print $@;
                    return 0;
                }
                return 1;
            },
        },
        'referrerblanksafety' => {
            'type' => 'binary',
        },
        'referrersafety' => {
            'type' => 'binary',
        },

        'dormant_services' => {
            'type' => 'multiselect',

            # Temporary. Hide cpanalyticsd conditionally. Will be removed in LC-8087.
            'options' => \@Cpanel::Config::Constants::DORMANT_SERVICES_LIST,
            'hidden'  => [ Cpanel::Config::DormantServices::get_hidden() ],
            'default' => {
                cpdavd  => 0,
                cphulkd => 0,
                cpsrvd  => 0,
            },
            'value' => sub {
                my $dormant = _current_system_value_for('dormant_services');
                return {} unless $dormant;
                return { map { $_ => 1 } split /\s*,\s*/, $dormant };
            },
            'action' => sub {

                #cpanel.config guard safe
                my $new_hr = shift;
                my $old_hr = $Conf{'dormant_services'}{'value'}->();

                my @all_keys         = Cpanel::ArrayFunc::Uniq::uniq( keys(%$new_hr), keys(%$old_hr) );
                my $sdir             = $Cpanel::ConfigFiles::DORMANT_SERVICES_DIR;
                my $made_dormant_dir = -d $sdir;
                my $restart          = 0;

                my @disabled = Cpanel::Config::DormantServices::get_hidden();

                for my $service (@all_keys) {
                    if ( $new_hr->{$service} ) {
                        if ( !$old_hr->{$service} ) {
                            require Cpanel::SafeDir::MK;
                            if ( !$made_dormant_dir ) {
                                Cpanel::SafeDir::MK::safemkdir($sdir);
                            }
                            Cpanel::SafeDir::MK::safemkdir("$sdir/$service");
                            _set_touch_file( "$sdir/$service/enabled", 1 );
                            $restart = 1;
                        }
                    }
                    elsif ( $old_hr->{$service} && !grep { $_ eq $service } @disabled ) {
                        unlink "$sdir/$service/enabled";
                        $restart = 1;
                    }
                    if ($restart) {

                        # Schedule in a second.
                        eval {
                            Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 1, "restartsrv $service --hard" );
                            1;
                        } or do {
                            print $@;
                            return 0;
                        };
                    }
                }

                return 1;
            },
            'label' => 'Dormant services',
            'help'  => "Use of the dormant service feature will decrease memory use. When a service is idle for 5 minutes, it will unload itself from memory, leaving a tiny “listening” service in place. The reduction in memory consumption is offset by a delay in fulfilling the initial request when dormant since full service must then be activated.",
        },
        'cookieipvalidation' => {
            'type'    => 'radio',
            'options' => [qw(disabled loose strict)],
        },
        'debughooks' => {
            'type'        => 'radio',
            'options'     => [qw(0 log logdata logall)],
            'value'       => \&Cpanel::Debug::Hooks::get_current_value,
            'post_action' => sub {
                my ( $new_value, $current_value, $force ) = @_;
                return 1 if ( !$force && $new_value eq $current_value );
                return Cpanel::Debug::Hooks::set_value($new_value);
            },
        },
        'debugui' => {
            'type'    => 'radio',
            'options' => [qw(0 1)],
        },
        'coredump' => {
            'type' => 'binary',
        },
        'requiressl' => {
            'type'        => 'binary',
            'post_action' => sub {

                # may be cpconfguard unsafe
                my ( $val, $oldval, $force ) = @_;
                return 1 if ( !$force && $val eq $oldval );
                return 1 if !Cpanel::Config::Httpd::EA4::is_ea4();

                if ( $force || !defined($oldval) || $val ne $oldval ) {
                    _schedule_cpservices_task('restartsrv cpdavd');
                }

                my $short_version = Cpanel::HttpUtils::Version::get_current_apache_version_key();
                if ( $short_version && $val ) {
                    $short_version = substr( $short_version, 0, 1 );
                    require Cpanel::SafeRun::Errors;
                    my $output = Cpanel::SafeRun::Errors::saferunnoerror(
                        'grep',
                        'RewriteRule ^/(.*) https://127.0.0.1:2087/$1 \[P\]',
                        '/var/cpanel/templates/apache' . $short_version . '/main.default',
                    );
                    unless ($output) {
                        eval { Cpanel::ServerTasks::queue_task( ['ApacheTasks'], 'build_apache_conf', 'apache_restart --force' ); };
                        if ($@) {
                            print $@;
                            return 0;
                        }
                    }
                }

                return 1;
            },
        },
        'ssl_default_key_type' => {
            'type'         => 'radio',
            'options'      => [ Cpanel::SSL::DefaultKey::Constants::OPTIONS() ],
            'optionlabels' => {
                Cpanel::SSL::DefaultKey::Constants::OPTIONS_AND_LABELS(),
            },
            'hidden'      => 1,
            'post_action' => sub {
                Cpanel::ServerTasks::queue_task( ['SSLTasks'], 'autossl_check' );
            },
        },
        'disable_cphttpd' => {
            type          => 'binary',
            'post_action' => sub {
                require Cpanel::Services::Enabled;
                _queue_cpsrvd_restart() if !Cpanel::Services::Enabled::is_enabled('httpd');
                return;
            },
        },
        'xframecpsrvd' => {
            'type'        => 'binary',
            'default'     => 1,
            'post_action' => sub {
                return _queue_cpsrvd_restart();
            },
        },
        'ssh_host_key_checking' => {
            'type'    => 'radio',
            'options' => [qw(disabled enabled dns)],
            'default' => 'disabled',
            'format'  => sub {
                my ($val) = @_;
                return 'disabled' if !$val;
                return 'enabled'  if $val eq '1';
                return $val;
            },
            'checkval' => sub {
                my ($val) = @_;

                return 0 if $val eq 'disabled';
                return 1 if $val eq 'enabled';
                return $val;
            },
            'post_action' => sub {
                return _queue_cpsrvd_restart();
            },
        },
        'dns_recursive_query_pool_size' => {
            type     => 'number',
            checkval => sub {
                my $value = shift;

                return !defined($value) || _is_natural_number($value);
            },
            'maxlength' => '3',
            can_undef   => 1,
        },
        'dnsadminapp' => {
            'can_undef' => 1,
            'type'      => 'path',
            'format'    => sub { return length $_[0] ? $_[0] : () },
            'checkval'  => sub {
                my $value = shift();

                return $value =~ m{\A/} && -x $value
                  ? $value
                  : ( undef, "Value must be a full path" );
            },
        },
        'check_zone_owner' => {
            'type' => 'binary',
        },
        'check_zone_syntax' => {
            'type' => 'binary',
        },
        'useauthnameservers' => {
            'type' => 'binary',
        },
        'autocreateaentries' => {
            'type' => 'binary',
        },
        'publichtmlsubsonly' => {
            needs_role   => 'WebServer',
            'ui_default' => 1,
            'type'       => 'binary',
        },
        'allowparkhostnamedomainsubdomains' => {
            'type' => 'binary',
        },
        'allowresellershostnamedomainsubdomains' => {
            'type' => 'binary',
        },
        'allowparkonothers' => {
            'type' => 'binary',
            skipif => \&_solo_license,
        },
        'allowwhmparkonothers' => {
            'type' => 'binary',
            skipif => \&_solo_license,
        },
        'allowremotedomains' => {
            'type' => 'binary',
        },
        'allowunregistereddomains' => {
            'type' => 'binary',
        },
        'blockcommondomains' => {
            'type' => 'binary',
        },
        'share_docroot_default' => {
            'type' => 'binary',
        },
        'proxysubdomains' => {
            'type'   => 'binary',
            'action' => sub {
                my ( $val, $oldval, $force, $new_config_hr, $old_config_hr ) = @_;

                return 1 if ( !$force && $val eq $oldval );

                _save_proxysubdomains_old_autodiscover_host_for_post_action($old_config_hr);
                $PROXY_SUBDOMAINS_CHANGED_STATE = 1;
            },
            'post_action' => sub {

                #may be cpconf guard unsafe
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );
                return 1 if !Cpanel::Config::Httpd::EA4::is_ea4();

                my $host_argument = ( $PROXY_SUBDOMAINS_OLD_AUTODISCOVER_HOST || $Cpanel::Proxy::Tiny::DEFAULT_AUTODISCOVERY_HOST );
                if ($val) {
                    eval {
                        Cpanel::ServerTasks::queue_task( ['ProxySubdomains'], "add_proxy_subdomains $host_argument" );
                        Cpanel::ServerTasks::queue_task( ['ApacheTasks'], 'build_apache_conf', 'apache_restart' );
                    };
                    if ($@) {
                        print $@;
                        return 0;
                    }
                    print "Creating service subdomain DNS entries in background. This process can take several minutes to complete.\n";

                }
                else {
                    eval {
                        Cpanel::ServerTasks::queue_task( ['ProxySubdomains'], "remove_proxy_subdomains $host_argument" );
                        Cpanel::ServerTasks::queue_task( ['ApacheTasks'], 'build_apache_conf', 'apache_restart' );
                    };
                    if ($@) {
                        print $@;
                        return 0;
                    }
                    print "Removing service subdomain DNS entries in background. This process can take several minutes to complete.\n";

                }
            },
        },
        'overwritecustomproxysubdomains' => {
            'type'     => 'binary',
            'requires' => 'proxysubdomains',
        },
        'overwritecustomsrvrecords' => {
            'type'     => 'binary',
            'requires' => 'autodiscover_proxy_subdomains',
        },
        'autodiscover_host' => {
            needs_role     => 'MailReceive',
            'default_text' => $Cpanel::Proxy::Tiny::DEFAULT_AUTODISCOVERY_HOST,
            'requires'     => 'autodiscover_proxy_subdomains',
            'type'         => 'path',
            'action'       => sub {

                #cpanel.config guard safe
                my ( $val, $oldval ) = @_;
                if ( !Cpanel::Validate::Domain::Tiny::validdomainname($val) ) {
                    print "Host is not a valid domain name.\n";
                    return 0;
                }

                # It is not safe to force this -- see case 104709
                return 1 if ( $val eq $oldval );

                $oldval ||= $Cpanel::Proxy::Tiny::DEFAULT_AUTODISCOVERY_HOST;

                if ($PROXY_SUBDOMAINS_AUTODISCOVER_ADD_SCHEDULED) {    # prevent autodiscover_proxy_subdomains from being updated from the 'autodiscover_proxy_subdomains' tweak setting
                    return 1;
                }
                $PROXY_SUBDOMAINS_AUTODISCOVER_ADD_SCHEDULED = 1;
                eval { Cpanel::ServerTasks::queue_task( ['ProxySubdomains'], 'update_autodiscover_proxy_subdomains ' . $oldval ); };
                if ($@) {
                    print $@;
                    return 0;
                }

                print "Updating service subdomain DNS entries in background. This process can take several minutes to complete.\n";
            }
        },
        'autodiscover_mail_service' => {
            needs_role => 'MailReceive',
            'type'     => 'radio',
            'options'  => [qw(imap pop3)],
            'requires' => 'autodiscover_proxy_subdomains',
            'ignoreif' => sub { return !$_[0]->{'proxysubdomains'} },
        },
        'autodiscover_proxy_subdomains' => {
            needs_role => 'MailReceive',
            'type'     => 'binary',
            'requires' => 'proxysubdomains',
            'default'  => 1,
            'action'   => sub {
                my ( $newval, $oldval, $force, $new_config_hr, $old_config_hr ) = @_;
                _save_proxysubdomains_old_autodiscover_host_for_post_action($old_config_hr);
            },
            'post_action' => sub {

                #may be cpconf guard unsafe
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );
                return 1 if !Cpanel::Config::Httpd::EA4::is_ea4();
                if ($PROXY_SUBDOMAINS_CHANGED_STATE) {
                    print "The master proxysubdomains setting changed state so we do not need to update the autodiscover domains.\n";
                    return 1;
                }
                my $host_argument = ( $PROXY_SUBDOMAINS_OLD_AUTODISCOVER_HOST || $Cpanel::Proxy::Tiny::DEFAULT_AUTODISCOVERY_HOST );
                if ($val) {
                    if ($PROXY_SUBDOMAINS_AUTODISCOVER_ADD_SCHEDULED) {    # This means we updated the service (formerly proxy) subdomains autodiscover host as we don't need to do an add as well
                        return 1;
                    }
                    $PROXY_SUBDOMAINS_AUTODISCOVER_ADD_SCHEDULED = 1;
                    eval { Cpanel::ServerTasks::queue_task( ['ProxySubdomains'], "add_autodiscover_proxy_subdomains $host_argument" ); };
                    if ($@) {
                        print $@;
                        return 0;
                    }

                    print "Creating service subdomain DNS entries in background. This process can take several minutes to complete.\n";
                }
                else {
                    eval { Cpanel::ServerTasks::queue_task( ['ProxySubdomains'], "remove_autodiscover_proxy_subdomains $host_argument" ); };
                    if ($@) {
                        print $@;
                        return 0;
                    }

                    print "Removing service subdomain DNS entries in background. This process can take several minutes to complete.\n";
                }

                Cpanel::ServerTasks::queue_task( ['ApacheTasks'], 'build_apache_conf', 'apache_restart' );

                return 1;
            },
        },
        'proxysubdomainsoverride' => {
            'type'     => 'binary',
            'requires' => 'proxysubdomains',
            'excludes' => 'overwritecustomproxysubdomains',
        },
        'domainowner_mail_pass' => {
            needs_role    => 'MailReceive',
            'type'        => 'binary',
            'post_action' => sub {

                #may be cpconf guard unsafe
                my ( $val, $oldval, $force ) = @_;

                my $return = _set_touch_file( '/var/cpanel/allow_domainowner_mail_pass', $val );

                if ( $force || !defined $oldval || $val ne $oldval ) {
                    _schedule_cpservices_task('restartsrv dovecot');
                }

                return $return;
            },
            'value' => sub { return _current_system_value_for('domainowner_mail_pass') },
        },
        'email_account_quota_userdefined_default_value' => {
            needs_role => 'MailReceive',
            'checkval' => \&_is_natural_number,
            'maximum'  => Cpanel::Email::Maildir::get_max_email_quota_mib(),
            'default'  => Cpanel::Email::Maildir::get_default_email_quota_mib(),
            'type'     => 'number',
            'unit'     => 'MB',
            'width'    => 7,
        },
        'email_account_quota_default_selected' => {
            needs_role => 'MailReceive',
            'type'     => 'radio',
            'options'  => [qw(unlimited userdefined)],
        },
        'defaultmailaction' => {
            needs_role => 'MailReceive',
            'type'     => 'radio',
            'options'  => [qw(localuser fail blackhole)],
        },
        'exim-retrytime' => {
            'skipif' => sub {
                return ( !Cpanel::Config::Services::service_enabled('exim') )
                  ? 1
                  : 0;
            },
            'checkval'    => \&_is_natural_number,
            'type'        => 'number',
            'unit'        => 'm',
            'width'       => 4,
            'default'     => 15,
            'post_action' => sub {

                #restartsrv is unsafe
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && defined $oldval && $val eq $oldval );

                require Whostmgr::Exim::Sysconfig;
                Whostmgr::Exim::Sysconfig::update_sysconfig($val);

                _schedule_cpservices_task('restartsrv exim');
                return 1;
            },
        },
        'eximmailtrap' => {
            'skipif' => sub {
                return if Cpanel::Config::Services::service_enabled('exim');
                return 1;
            },
            'type'   => 'binary',
            'value'  => sub { return _current_system_value_for('eximmailtrap') },
            'action' => sub {

                #cpanel.config guard safe
                my $val = shift;
                return _set_touch_file( '/etc/eximmailtrap', $val );
            },
        },
        'email_send_limits_max_defer_fail_percentage' => {
            'skipif'    => sub { return !Cpanel::Config::Services::service_enabled('exim'); },
            'type'      => 'number',
            'unit'      => '%',
            'maxlength' => 3,
            'checkval'  => \&_is_positive_percentage_integer,
            'can_undef' => 1,
        },
        'email_send_limits_count_mailman' => {
            'skipif'   => sub { return !Cpanel::Config::Services::service_enabled('exim'); },
            'type'     => 'binary',
            'excludes' => 'skipmailman',
            'action'   => sub {

                #cpanel.config guard safe
                my ($newval) = @_;
                mkdir( '/var/cpanel/email_send_limits', 0751 ) if !-e '/var/cpanel/email_send_limits';
                return _set_touch_file( '/var/cpanel/email_send_limits/count_mailman', $newval );
            },
            'value' => sub {
                return -e '/var/cpanel/email_send_limits/count_mailman' ? 1 : 0;
            }
        },
        'email_send_limits_defer_cutoff' => {
            'skipif'   => sub { return !Cpanel::Config::Services::service_enabled('exim'); },
            'checkval' => sub {
                my $val = shift();
                return $val =~ m{\A(\d+)\z} && $1 >= 100 && $1 <= 10000
                  ? int $val
                  : ( undef, "Value must be a number between 100 and 10000" );
            },
            'maximum'   => 10000,
            'unit'      => '%',
            'maxlength' => 5,
            'minimum'   => 100,
            'can_undef' => 0,
            'type'      => 'number',
            'action'    => sub {

                #cpanel.config guard safe
                my $percentage = int shift;
                mkdir( '/var/cpanel/email_send_limits', 0751 ) if !-e '/var/cpanel/email_send_limits';

                # The value is the size of the file so we can avoid the open/close overhead (just a stat)
                if ( open( my $cut_off_percentage_fh, '>', '/var/cpanel/email_send_limits/defer_cutoff' ) ) {
                    print {$cut_off_percentage_fh} 'x' x $percentage;
                    close($cut_off_percentage_fh);
                }
                return 1;
            },
            'value' => sub {

                # The value is the size of the file so we can avoid the open/close overhead (just a stat)
                my $cut_off_percentage = ( stat('/var/cpanel/email_send_limits/defer_cutoff') )[7];
                if ( !defined $cut_off_percentage ) { $cut_off_percentage = $DEFAULT_EMAIL_SEND_LIMITS_DEFER_CUTOFF_PERCENTAGE; }
                return $cut_off_percentage;
            }
        },
        'email_send_limits_min_defer_fail_to_trigger_protection' => {
            'skipif'      => sub { return !Cpanel::Config::Services::service_enabled('exim'); },
            'checkval'    => \&_is_natural_number,
            'default'     => 5,
            'can_undef'   => 0,
            'type'        => 'number',
            'post_action' => sub {
                my ($current) = @_;

                # Update the cached value since it never invalidates
                $Cpanel::Email::DeferThreshold::cached_defer_threshold = $current;

                # Tailwatchd runs in a different process, we need to restart it since it will be using a cached value
                _schedule_cpservices_task('restartsrv tailwatchd');
                return 1;
            },
        },
        'email_outbound_spam_detect_enable' => {
            needs_role => 'SpamFilter',
            'type'     => 'binary',
            'skipif'   => sub { return 1 if !Cpanel::Config::Services::service_enabled('exim'); },
        },
        'email_outbound_spam_detect_action' => {
            needs_role => 'SpamFilter',
            'type'     => 'radio',
            'options'  => [qw(noaction hold block)],
            'requires' => 'email_outbound_spam_detect_enable',
            'skipif'   => sub { return 1 if !Cpanel::Config::Services::service_enabled('exim'); },
        },
        'email_outbound_spam_detect_threshold' => {
            needs_role  => 'SpamFilter',
            'requires'  => 'email_outbound_spam_detect_enable',
            'skipif'    => sub { return 1 if !Cpanel::Config::Services::service_enabled('exim'); },
            'checkval'  => \&_is_natural_number,
            'default'   => 500,
            'can_undef' => 0,
            'type'      => 'number',
        },
        'mailbox_storage_format' => {
            needs_role => 'MailReceive',
            'type'     => 'radio',
            'options'  => [qw(mdbox maildir)],
            'default'  => $cpconf_defaults_hr->{'mailbox_storage_format'},
        },
        'autoupdate_certificate_on_hostname_mismatch' => {
            'type'   => 'binary',
            'action' => sub {
                my ($newval) = @_;

                # touch a file when off (0) and unlink file when on (1)
                return _set_touch_file( '/var/cpanel/ssl/disable_hostname_mismatch_check', $newval == 1 ? 0 : 1 );
            },
            'value' => sub {
                return !-e '/var/cpanel/ssl/disable_hostname_mismatch_check' ? 1 : 0;
            },
        },
        'ipv6_listen' => {
            'type'   => 'binary',
            'action' => sub {
                my ($newval) = @_;
                return _set_touch_file( '/var/cpanel/ipv6_listen', $newval );
            },
            'value' => sub {
                return -e '/var/cpanel/ipv6_listen' ? 1 : 0;
            },
        },
        'maxemailsperhour' => {
            'skipif'    => sub { return !Cpanel::Config::Services::service_enabled('exim'); },
            'checkval'  => \&_is_natural_number,
            'can_undef' => 1,
            'type'      => 'number',
            'action'    => sub {

                #cpanel.config guard safe
                # maxemailsperhour is NOT a touch file
                # as it contains a single integer value
                my ( $newval, $oldval, $force ) = @_;
                $newval ||= 0;
                $oldval ||= 0;
                return 1 if ( !$force && $newval eq $oldval );
                if ($newval) {
                    Cpanel::FileUtils::Write::overwrite( '/var/cpanel/maxemailsperhour', $newval, 0644 );
                }
                else {
                    unlink('/var/cpanel/maxemailsperhour');
                }
            },

        },
        'emailsperdaynotify' => {
            'skipif'    => sub { return !Cpanel::Config::Services::service_enabled('exim'); },
            'checkval'  => \&_is_natural_number,
            'can_undef' => 1,
            'type'      => 'number',
            'action'    => sub {

                #cpanel.config guard safe
                my $limit = shift;
                $limit ||= 0;
                $limit = int($limit);
                mkdir( '/var/cpanel/email_send_limits', 0751 ) if !-e '/var/cpanel/email_send_limits';

                if ( $limit == 0 ) {
                    unlink '/var/cpanel/email_send_limits/daily_limit_notify';
                    return 1;
                }

                # The value is the size of the file so we can avoid the open/close overhead (just a stat)
                if ( open( my $daily_limit_fh, '>', '/var/cpanel/email_send_limits/daily_limit_notify' ) ) {
                    print {$daily_limit_fh} 'x' x $limit;
                    close($daily_limit_fh);
                }
                return 1;
            },
        },
        'mycnf_auto_adjust_innodb_buffer_pool_size' => {
            needs_role    => 'MySQL',
            'skipif'      => sub { return !Cpanel::Config::Services::service_enabled('mysql') },
            'default'     => 0,
            'can_undef'   => 0,
            'type'        => 'binary',
            'post_action' => sub {
                my ( $current, $old ) = @_;
                return 1 unless $current && !$old;
                return _queue_mysql_restart();
            }
        },
        'mycnf_auto_adjust_maxallowedpacket' => {
            needs_role    => 'MySQL',
            'skipif'      => sub { return !Cpanel::Config::Services::service_enabled('mysql') },
            'default'     => 1,
            'can_undef'   => 0,
            'type'        => 'binary',
            'post_action' => sub {
                my ( $current, $old ) = @_;
                return 1 unless $current && !$old;
                return _queue_mysql_restart();

            }
        },
        'mycnf_auto_adjust_openfiles_limit' => {
            needs_role    => 'MySQL',
            'skipif'      => sub { return !Cpanel::Config::Services::service_enabled('mysql') },
            'default'     => 1,
            'can_undef'   => 0,
            'type'        => 'binary',
            'post_action' => sub {
                my ( $current, $old ) = @_;
                return 1 unless $current && !$old;
                return _queue_mysql_restart();
            }
        },
        'nobodyspam' => {
            needs_role => 'WebServer',
            'type'     => 'binary',
            'value'    => sub { return -e '/etc/webspam' ? 1 : 0; },
            'action'   => sub {

                #cpanel.config guard safe
                my ($val) = @_;
                return _set_touch_file( '/etc/webspam', $val );
            },
        },
        'popbeforesmtp' => {
            needs_role => 'MailReceive',
            'skipif'   => sub {
                return 0 if Cpanel::Config::Services::service_enabled('exim');
                return 1;
            },
            'type'        => 'binary',
            'excludes'    => 'skiprecentauthedmailiptracker',
            'value'       => sub { return -e '/etc/popbeforesmtp' ? 1 : 0; },
            'post_action' => sub {

                #cpanel.config guard safe
                my ($val) = @_;
                return _set_touch_file( '/etc/popbeforesmtp', $val );
            },
        },
        'popbeforesmtpsenders' => {
            needs_role => 'MailReceive',
            'skipif'   => sub {
                return 0 if Cpanel::Config::Services::service_enabled('exim');
                return 1;
            },
            'requires' => 'popbeforesmtp',
            'excludes' => 'skiprecentauthedmailiptracker',
            'type'     => 'binary',
            'value'    => sub { return -e '/etc/eximpopbeforesmtpwarning' ? 1 : 0; },
            'action'   => sub {

                #cpanel.config guard safe
                my ($val) = @_;
                return _set_touch_file( '/etc/eximpopbeforesmtpwarning', $val );
            },
        },
        'emailarchive' => {
            needs_role => 'MailReceive',
            'skipif'   => sub {
                return if Cpanel::Config::Services::service_enabled('exim');
                return 1;
            },
            'type'        => 'binary',
            'post_action' => sub {
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );
                eval { Cpanel::ServerTasks::queue_task( [ 'EximTasks', 'CpServicesTasks' ], 'buildeximconf --restart', "restartsrv imap" ); };
                if ($@) {
                    print $@;
                    return 0;
                }
                return 1;
            }
        },
        'skipboxtrapper' => {
            needs_role => 'MailReceive',
            'skipif'   => sub {
                return if Cpanel::Config::Services::service_enabled('exim');
                return 1;
            },
            'type'        => 'inversebinary',
            'post_action' => sub {
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );
                eval { Cpanel::ServerTasks::queue_task( ['EximTasks'], 'buildeximconf --restart' ); };
                if ($@) {
                    print $@;
                    return 0;
                }
                return 1;
            }
        },
        'skiproundcube' => {
            needs_role => 'MailReceive',
            'type'     => 'inversebinary',
        },
        'skipmailman' => {
            needs_role    => 'MailReceive',
            'type'        => 'inversebinary',
            'post_action' => sub {
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );
                my $enabled = $val ? 0 : 1;    # its a 'skip'
                Cpanel::LoadModule::load_perl_module('Whostmgr::Services');
                Whostmgr::Services::disable('mailman') if !$enabled;    #will stop it
                Whostmgr::Services::enable('mailman')  if $enabled;     #will restart it
                system '/usr/local/cpanel/bin/mailman-tool';

                # We must restart apache so that the mailman URLs enabled/disabled
                Cpanel::ServerTasks::schedule_task( ['ApacheTasks'], 10, 'apache_restart' );
                return 1;
            }
        },
        'skipspamassassin' => {
            needs_role      => 'SpamFilter',
            'requires_test' => [ Cpanel::Server::Type::Role::SpamFilter->is_enabled(), '==', '1' ],
            'skipif'        => sub {
                return if Cpanel::Config::Services::service_enabled('exim');
                return 1;
            },
            'type'        => 'inversebinary',
            'post_action' => sub {

                #may be cpconfguard unsafe
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );
                if ($val) {
                    _run_in_background( cmd => [ '/usr/local/cpanel/etc/init/kill_apps_on_ports', 783 ] );
                    _run_in_background( cmd => [ '/usr/local/cpanel/scripts/spamassassindisable', '-f' ] );
                    return 1;
                }
                else {
                    _run_in_background( cmd => [ '/usr/local/cpanel/scripts/spamassassindisable', '-f', '--undo' ] );
                    _schedule_cpservices_task('restartsrv spamd');
                    return 1;
                }
            },
        },
        'skipspambox' => {
            needs_role => 'SpamFilter',
            'skipif'   => sub {
                return if Cpanel::Config::Services::service_enabled('exim');
                return 1;
            },
            'type'   => 'inversebinary',
            'skipif' => sub {
                my $cpconf_ref = shift;
                return 1 if ( $cpconf_ref->{'skipspamassassin'} );
                return 0;
            },
            'post_action' => sub {

                #may be cpconf guard unsafe
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );
                if ($val) {
                    if ( -x '/usr/local/cpanel/scripts/spamboxdisable' ) {
                        _run_in_background( cmd => [ '/usr/local/cpanel/scripts/spamboxdisable', '-f' ] );
                        return 1;
                    }
                    return 0;
                }
                else {
                    return 1;
                }
            },
        },
        'smtpmailgidonly' => {
            'ui_default'  => 1,
            'type'        => 'binary',
            'value'       => sub { return ( -e '/var/cpanel/smtpgidonlytweak' ) ? 1 : 0 },
            'post_action' => sub {

                #may be cpconfguard unsafe
                my ( $newval, $oldval, $force ) = @_;
                my $enable  = $newval  && ( !$oldval || $force );
                my $disable = !$newval && ( $oldval  || $force );
                if ($enable) {
                    require Cpanel::SafeRun::Errors;
                    my $output = Cpanel::SafeRun::Errors::saferunnoerror( '/usr/local/cpanel/scripts/smtpmailgidonly', 'on' );
                    return 0 unless $output =~ m/enabled/i;
                }
                elsif ($disable) {
                    require Cpanel::SafeRun::Errors;
                    my $output = Cpanel::SafeRun::Errors::saferunnoerror( '/usr/local/cpanel/scripts/smtpmailgidonly', 'off' );
                    return 0 unless $output =~ m/disabled/i;
                }
                return 1;
            },
        },
        'usemailformailmanurl' => {
            needs_role    => 'MailReceive',
            'type'        => 'binary',
            'excludes'    => 'skipmailman',
            'post_action' => sub {

                #may be cpconfguard unsafe
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );
                system '/usr/local/cpanel/scripts/resetmailmanurls';
                return 1;
            },
        },
        'use_information_schema' => {    # XXX TODO?? Remote MySQL … ??
            'type'     => 'binary',
            'requires' => 'disk_usage_include_sqldbs',
        },
        'disk_usage_include_mailman' => {
            needs_role    => 'MailReceive',
            'type'        => 'binary',
            'excludes'    => 'skipmailman',
            'post_action' => sub {

                #may be cpconfguard unsafe
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );
                Cpanel::LoadModule::load_perl_module('Cpanel::SysQuota::Cache');
                Cpanel::SysQuota::Cache::purge_cache();
                _run_in_background( nowait => 1, cmd => ['/usr/local/cpanel/scripts/update_mailman_cache'] );
                return;
            },
        },
        'disk_usage_include_sqldbs' => {    # XXX TODO?? Remote MySQL … ??
            'type'        => 'binary',
            'post_action' => sub {

                # may be cpconfguard unsafe
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );
                Cpanel::LoadModule::load_perl_module('Cpanel::SysQuota::Cache');
                Cpanel::SysQuota::Cache::purge_cache();
                _run_in_background( nowait => 1, cmd => ['/usr/local/cpanel/scripts/update_db_cache'] );
                return;
            },
        },
        'usemysqloldpass' => {    # XXX TODO?? Can we remove this … ??
            'skipif' => sub {
                my $cpconf_ref = shift;

                return 1 if !Cpanel::Config::Services::service_enabled('mysql');

                # Don't skip if a change is being made.
                my $current_conf_ref = Cpanel::Config::CpConfGuard->new( use_lock => 0 )->{'data'};
                return 0 if $current_conf_ref->{'usemysqloldpass'} ne $cpconf_ref->{'usemysqloldpass'};

                return 1 if $cpconf_ref->{'mysql-version'} && $cpconf_ref->{'mysql-version'} >= 5.6 && !$cpconf_ref->{'usemysqloldpass'};

                return;
            },
            'type'        => 'binary',
            'post_action' => sub {

                #definately cpconfguard unsafe
                my $val    = shift;
                my $oldval = shift;

                my $mysql_conf = '/etc/my.cnf';

                if ( -e $mysql_conf ) {
                    if ( open my $cnf_fh, '<', $mysql_conf ) {

                        my $hasmysqld       = 0;
                        my $hasoldpasswords = 0;
                        my $inmysqld        = 0;
                        my @cnf;

                        while ( my $line = readline $cnf_fh ) {
                            if ( $line =~ m/\[mysqld]/ ) {
                                $inmysqld  = 1;
                                $hasmysqld = 1;
                                push @cnf, $line;
                                next;
                            }

                            if ($inmysqld) {
                                if ( $line =~ m/\[\w+\]/ ) {
                                    if ( !$hasoldpasswords && $val ) {

                                        #print "Adding old-passwords option\n";
                                        $hasoldpasswords = 1;

                                        # Keep a blank line between groupings.
                                        if ( $cnf[$#cnf] =~ m/^\s*$/ ) {
                                            pop @cnf;
                                            push @cnf, "old-passwords = 1\n\n";
                                        }
                                        else {
                                            push @cnf, "old-passwords = 1\n\n";
                                        }
                                    }
                                    $inmysqld = 0;
                                    push @cnf, $line;
                                    next;
                                }
                                if ( $line =~ m/old-passwords/ ) {
                                    if ($val) {

                                        #print "Has old-passwords option\n";
                                        push @cnf, "old-passwords = 1\n";
                                        $hasoldpasswords = 1;
                                        next;
                                    }
                                    elsif ( !$val ) {

                                        #print "Removing old-passwords option\n";
                                        next;
                                    }
                                }
                            }
                            push @cnf, $line;
                        }
                        close $cnf_fh;

                        # mysqld did not exist or was last group
                        if ( $val && !$hasoldpasswords ) {
                            if ( !$hasmysqld ) {
                                push @cnf, "[mysqld]\n";
                            }
                            push @cnf, "old-passwords = 1\n\n";
                        }

                        if ( open my $new_cnf_fh, '>', $mysql_conf ) {

                            #print "Writing new config\n";
                            print {$new_cnf_fh} join '', @cnf;
                            close $new_cnf_fh;
                            return 1;
                        }
                        else {
                            return 0;
                        }

                    }
                }

                # Restart MySQL if necessary
                if ( $val ne $oldval ) {
                    _queue_mysql_restart();
                }

                return 1;
            },
        },
        'skipoomcheck' => {
            'type' => 'inversebinary',
        },
        'skipdiskcheck' => {
            'type' => 'inversebinary',
        },
        'skipdiskusage' => {
            'type'   => 'inversebinary',
            'action' => sub {

                #cpanel.config guard safe
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );

                eval { Cpanel::ServerTasks::queue_task( ['TailwatchTasks'], 'reloadtailwatch' ); };
                if ($@) {
                    print $@;
                    return 0;
                }
                return 1;
            },
        },
        'emailusers_diskusage_full_percent' => {
            needs_role  => 'MailReceive',
            'type'      => 'number',
            'unit'      => '%',
            'maxlength' => 7,
            'checkval'  => \&_is_positive_percentage_float,
            'can_undef' => 1,
            'excludes'  => 'skipdiskcheck',
        },
        'emailusers_diskusage_full_contact_admin' => {
            needs_role => 'MailReceive',
            'type'     => 'binary',
            'requires' => 'emailusers_diskusage_full_percent',
            'excludes' => 'skipdiskcheck',
        },
        'emailusers_diskusage_critical_percent' => {
            needs_role  => 'MailReceive',
            'type'      => 'number',
            'unit'      => '%',
            'maxlength' => 7,
            'checkval'  => \&_is_positive_percentage_float,
            'can_undef' => 1,
            'excludes'  => 'skipdiskcheck',
        },
        'emailusers_diskusage_critical_contact_admin' => {
            needs_role => 'MailReceive',
            'type'     => 'binary',
            'requires' => 'emailusers_diskusage_critical_percent',
            'excludes' => 'skipdiskcheck',
        },

        'emailusers_diskusage_warn_percent' => {
            needs_role  => 'MailReceive',
            'type'      => 'number',
            'unit'      => '%',
            'maxlength' => 7,
            'checkval'  => \&_is_positive_percentage_float,
            'can_undef' => 1,
            'excludes'  => 'skipdiskcheck',
        },
        'emailusers_diskusage_warn_contact_admin' => {
            needs_role => 'MailReceive',
            'type'     => 'binary',
            'requires' => 'emailusers_diskusage_warn_percent',
            'excludes' => 'skipdiskcheck',
        },
        'system_diskusage_critical_percent' => {
            'type'      => 'number',
            'unit'      => '%',
            'maxlength' => 7,
            'checkval'  => \&_is_positive_percentage_float,
            'can_undef' => 1,
            'excludes'  => 'skipdiskusage',
            'action'    => sub {

                #cpanel.config guard safe
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );

                eval { Cpanel::ServerTasks::queue_task( ['TailwatchTasks'], 'reloadtailwatch' ); };
                if ($@) {
                    print $@;
                    return 0;
                }
                return 1;
            },
            'ignoreif' => sub { return $_[0]->{'skipdiskusage'} },
        },
        'system_diskusage_warn_percent' => {
            'type'      => 'number',
            'unit'      => '%',
            'maxlength' => 7,
            'checkval'  => \&_is_positive_percentage_float,
            'can_undef' => 1,
            'excludes'  => 'skipdiskusage',
            'action'    => sub {

                #cpanel.config guard safe
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );

                eval { Cpanel::ServerTasks::queue_task( ['TailwatchTasks'], 'reloadtailwatch' ); };
                if ($@) {
                    print $@;
                    return 0;
                }
                return 1;
            },
            'ignoreif' => sub { return $_[0]->{'skipdiskusage'} },
        },
        'skipboxcheck' => {
            needs_role => 'MailReceive',
            'type'     => 'inversebinary',
        },

        'emailusers_mailbox_full_percent' => {
            needs_role  => 'MailReceive',
            'type'      => 'number',
            'unit'      => '%',
            'maxlength' => 7,
            'checkval'  => \&_is_positive_percentage_float,
            'can_undef' => 1,
            'excludes'  => 'skipboxcheck',
            'ignoreif'  => sub { return $_[0]->{'skipboxcheck'} },
        },
        'emailusers_mailbox_critical_percent' => {
            needs_role  => 'MailReceive',
            'type'      => 'number',
            'unit'      => '%',
            'maxlength' => 7,
            'checkval'  => \&_is_positive_percentage_float,
            'can_undef' => 1,
            'excludes'  => 'skipboxcheck',
            'ignoreif'  => sub { return $_[0]->{'skipboxcheck'} },
        },
        'emailusers_mailbox_warn_percent' => {
            needs_role  => 'MailReceive',
            'type'      => 'number',
            'unit'      => '%',
            'maxlength' => 7,
            'checkval'  => \&_is_positive_percentage_float,
            'can_undef' => 1,
            'excludes'  => 'skipboxcheck',
            'ignoreif'  => sub { return $_[0]->{'skipboxcheck'} },
        },
        'notify_expiring_certificates' => {
            needs_role => 'UserSSL',
            'type'     => 'binary',
        },
        'skipbwlimitcheck' => {
            needs_role => 'WebServer',
            'type'     => 'inversebinary',
            'value'    => sub { return -e '/var/cpanel/bwlimitcheck.disabled' ? 1 : 0; },
            'action'   => sub {

                #cpanel.config guard safe
                my ($val) = @_;

                system 'rm -f -- /var/cpanel/bwlimited/*' if ($val);

                return _set_touch_file( '/var/cpanel/bwlimitcheck.disabled', $val );
            },
        },
        'cgihidepass' => {
            needs_role => 'WebServer',
            'type'     => 'binary',
        },
        'emailusersbandwidthexceed99' => {
            needs_role => 'MailReceive',
            'type'     => 'binary',
            'requires' => 'emailusersbandwidthexceed',
            'excludes' => 'skipbwlimitcheck',
        },
        'emailusersbandwidthexceed98' => {
            needs_role => 'MailReceive',
            'type'     => 'binary',
            'requires' => 'emailusersbandwidthexceed',
            'excludes' => 'skipbwlimitcheck',
        },
        'emailusersbandwidthexceed97' => {
            needs_role => 'MailReceive',
            'type'     => 'binary',
            'requires' => 'emailusersbandwidthexceed',
            'excludes' => 'skipbwlimitcheck',
        },
        'emailusersbandwidthexceed95' => {
            needs_role => 'MailReceive',
            'type'     => 'binary',
            'requires' => 'emailusersbandwidthexceed',
            'excludes' => 'skipbwlimitcheck',
        },
        'emailusersbandwidthexceed90' => {
            needs_role => 'MailReceive',
            'type'     => 'binary',
            'requires' => 'emailusersbandwidthexceed',
            'excludes' => 'skipbwlimitcheck',
        },
        'emailusersbandwidthexceed85' => {
            needs_role => 'MailReceive',
            'type'     => 'binary',
            'requires' => 'emailusersbandwidthexceed',
            'excludes' => 'skipbwlimitcheck',
        },
        'emailusersbandwidthexceed80' => {
            needs_role => 'MailReceive',
            'type'     => 'binary',
            'requires' => 'emailusersbandwidthexceed',
            'excludes' => 'skipbwlimitcheck',
        },
        'emailusersbandwidthexceed75' => {
            needs_role => 'MailReceive',
            'type'     => 'binary',
            'requires' => 'emailusersbandwidthexceed',
            'excludes' => 'skipbwlimitcheck',
        },
        'emailusersbandwidthexceed70' => {
            needs_role => 'MailReceive',
            'type'     => 'binary',
            'requires' => 'emailusersbandwidthexceed',
            'excludes' => 'skipbwlimitcheck',
        },
        'emailusersbandwidthexceed' => {
            needs_role => 'MailReceive',
            'type'     => 'binary',
            'excludes' => 'skipbwlimitcheck',
        },
        'php_memory_limit' => {    ## affects cP’s own PHP
            'maximum'   => 16384,
            'minimum'   => 128,
            'maxlength' => 5,
            'unit'      => 'MB',
            'type'      => 'size',
            'checkval'  => sub {
                my $val = shift();

                my $min = $Whostmgr::TweakSettings::Main::Conf{'php_memory_limit'}{'minimum'};
                my $max = $Whostmgr::TweakSettings::Main::Conf{'php_memory_limit'}{'maximum'};

                if ( $val && $val =~ m{\A(\d+)\s*M?\z}a && $1 <= $max && $1 >= $min ) {
                    return int $1;
                }
                else {
                    return ( undef, "Value must be a size in Megabytes less than or equal to $max and at least $min" );
                }
            },
            'format'      => sub { shift() =~ m{(\d+)}a && $1 },
            'post_action' => sub {

                # may be cpconfguard unsafe
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                $val //= '';
                if ( length $val ) { $val =~ s/\s//g; }
                return 1 if ( !$force && $val eq $oldval );
                if ( $val =~ m/^\d+M?$/a ) {
                    _checkphpini_and_install_php_inis();

                    # XXX The queued restart of cpanel_php_fpm has been replaced by scheduling this at the end of the above task.
                    return 1;
                }
                else {
                    return;
                }
            },
        },
        'php_post_max_size' => {    ## affects cP’s own PHP
            'maximum'   => 2047,
            'minimum'   => 55,
            'maxlength' => 5,
            'unit'      => 'MB',
            'type'      => 'size',
            'checkval'  => sub {
                my $val = shift();

                my $min = $Whostmgr::TweakSettings::Main::Conf{'php_post_max_size'}{'minimum'};
                my $max = $Whostmgr::TweakSettings::Main::Conf{'php_post_max_size'}{'maximum'};

                if ( $val && $val =~ m{\A(\d+)\s*M?\z} && $1 <= $max && $1 >= $min ) {
                    return int $1;
                }
                else {
                    return ( undef, "Value must be a size in Megabytes less than or equal to $max and at least $min" );
                }
            },
            'format'      => sub { shift() =~ m{(\d+)} && $1 },
            'post_action' => sub {

                # may be cpconfguard unsafe
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                if ($val) { $val =~ s/\s//g; }
                return 1 if ( !$force && $val eq $oldval );
                if ( $val =~ m/^\d+M?$/ ) {
                    _checkphpini_and_install_php_inis();

                    # XXX The queued restart of cpanel_php_fpm has been replaced by scheduling this at the end of the above task.
                    return 1;
                }
                else {
                    return;
                }
            },
        },
        'php_upload_max_filesize' => {
            'maximum'   => 2047,
            'minimum'   => 50,
            'type'      => 'size',
            'maxlength' => 5,
            'unit'      => 'MB',
            'format'    => sub { shift() =~ m{(\d+)} && $1 },
            'checkval'  => sub {
                my $val = shift();

                my $min = $Whostmgr::TweakSettings::Main::Conf{'php_upload_max_filesize'}{'minimum'};
                my $max = $Whostmgr::TweakSettings::Main::Conf{'php_upload_max_filesize'}{'maximum'};

                if ( $val && $val =~ m{\A(\d+)\s*M?\z} && $1 <= $max && $1 >= $min ) {
                    return int $1;
                }
                else {
                    return ( undef, "Value must be a size in Megabytes less than or equal to $max and at least $min" );
                }
            },
            'post_action' => sub {

                # may be cpconfguard unsafe
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                if ($val) { $val =~ s/\s//g; }
                return 1 if ( !$force && $val eq $oldval );
                if ( $val =~ m/^\d+M?$/ ) {
                    _checkphpini_and_install_php_inis();

                    # XXX The queued restart of cpanel_php_fpm has been replaced by scheduling this at the end of the above task.
                    return 1;
                }
                else {
                    return;
                }
            },
        },
        'php_max_execution_time' => {
            'type'     => 'number',
            'minimum'  => 90,
            'maximum'  => 500,
            'checkval' => sub {
                my $val = shift();

                my $min = $Whostmgr::TweakSettings::Main::Conf{'php_upload_max_filesize'}{'minimum'};
                my $max = $Whostmgr::TweakSettings::Main::Conf{'php_upload_max_filesize'}{'maximum'};

                if ( $val && $val =~ m{\A(\d+)\s*M?\z} && $1 >= $min && $1 <= $max ) {
                    return int $1;
                }
                else {
                    return ( undef, "Value must be at least $min seconds and no more than $max seconds" );
                }
            },
            'unit'        => 's',
            'width'       => 3,
            'post_action' => sub {

                # may be cpconfguard unsafe
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );
                if ( $val =~ m/^\d+$/ ) {
                    _checkphpini_and_install_php_inis();
                    return 1;
                }
                else {
                    return;
                }
            },
        },
        'phploader' => {
            'type'    => 'multiselect',
            'options' => [qw(ioncube sourceguardian)],
            'default' => {
                ioncube        => 0,
                sourceguardian => 0,
            },
            'value' => sub {
                my ($cpconf) = @_;
                Cpanel::Debug::log_warn("cpconf was not provided to phploader value") if !$cpconf;
                $cpconf ||= Cpanel::Config::CpConfGuard->new( use_lock => 0 )->{'data'};
                if ( defined $cpconf->{'phploader'} ) {
                    return { map { $_ => 1 } split( /,/, $cpconf->{'phploader'} ) };
                }
                return;
            },
            'post_action' => sub {
                my ( $val, $oldval, $force ) = @_;

                if ( ref $val ) {
                    foreach my $loader ( sort keys %$val ) {
                        if ( $loader =~ m/sourceguardian/ ) {
                            if ( -e '/var/cpanel/disablesourceguardian' ) {
                                unlink '/var/cpanel/disablesourceguardian';
                            }
                        }
                    }
                }

                _checkphpini_and_install_php_inis();
                return 1;
            },
        },
        'pma_disableis' => {    ## XXX TODO??
            'type'   => 'inversebinary',
            'skipif' => sub {
                return 1 if ( !-e '/usr/local/cpanel/base/3rdparty/phpMyAdmin/config.inc.php.in' );
                return 0;
            },
            'post_action' => sub {
                my ( $val, $oldval, $force ) = @_;

                if ( $force || !defined $oldval || $val ne $oldval ) {
                    _run_in_background( cmd => [ '/usr/local/cpanel/bin/update_phpmyadmin_config', '--force' ] );
                }

                return 1;
            },
            'label' => 'Enable phpMyAdmin information schema searches',
            'help'  => 'If between 100 and 1,000 databases exist on your server, you can disable this option to attempt to increase performance. However, cPanel users must relog in to cPanel to allow phpMyAdmin to display newly-created databases.',
        },
        'awstatsreversedns' => {
            needs_role => 'WebServer',
            'type'     => 'binary',
        },
        'empty_trash_days' => {
            needs_role => 'FileStorage',
            'checkval' => sub {
                my $val = shift;
                return $val if $val eq 'disabled';
                return _is_whole_number($val);
            },
            'default_text' => 'Disabled',
            'default'      => 'disabled',
            'type'         => 'text',
        },
        'skipanalog' => {
            needs_role    => 'WebServer',
            'type'        => 'inversebinary',
            'post_action' => sub {

                # may be cpconfguard unsafe
                my $val = shift;

                set_local_versions_target( !$val, 'analog', '/usr/local/cpanel/3rdparty/bin/analog' );
                return 1;
            },
        },
        'skipawstats' => {
            needs_role    => 'WebServer',
            'type'        => 'inversebinary',
            'post_action' => sub {

                # may be cpconfguard unsafe
                my $val = shift;

                set_local_versions_target( !$val, 'awstats', '/usr/local/cpanel/3rdparty/bin/awstats.pl' );
                return 1;
            },
        },
        'skipwebalizer' => {
            needs_role    => 'WebServer',
            'type'        => 'inversebinary',
            'post_action' => sub {

                # may be cpconfguard unsafe
                my $val = shift;

                set_local_versions_target( !$val, 'webalizer', '/usr/local/cpanel/3rdparty/bin/webalizer' );
                return 1;
            },
        },
        'awstatsbrowserupdate' => {
            needs_role => 'WebServer',
            'type'     => 'binary',
            'skipif'   => sub {
                my $cpconf_ref = shift;
                return 1 if ( $cpconf_ref->{'skipawstats'} );
                return 0;
            },
        },
        'default_archive-logs' => {
            needs_role => 'WebServer',
            'type'     => 'binary',
        },
        'default_remove-old-archived-logs' => {
            needs_role => 'WebServer',
            'type'     => 'binary',
            'requires' => 'default_archive-logs',
        },
        'dumplogs' => {
            needs_role => 'WebServer',
            'type'     => 'binary',
        },
        'extracpus' => {
            'checkval' => \&_is_whole_number,
            'type'     => 'number'
        },
        'keepftplogs' => {
            needs_role => 'FileStorage',
            'type'     => 'binary',
        },
        'keeplogs' => {
            needs_role => 'WebServer',
            'type'     => 'binary',
            'excludes' => 'dumplogs',
        },
        'keepstatslog' => {
            'type' => 'binary',
        },
        'rotatelogs_size_threshhold_in_megabytes' => {
            'minimum'  => 10,
            'type'     => 'number',
            'unit'     => 'MB',
            'width'    => 5,
            'checkval' => sub {
                my $val = shift();

                return $val && $val =~ m{\A\d+\z} && $val >= $Whostmgr::TweakSettings::Main::Conf{'rotatelogs_size_threshhold_in_megabytes'}{'minimum'}
                  ? $val
                  : ( undef, "Value must be a number above $Whostmgr::TweakSettings::Main::Conf{'rotatelogs_size_threshhold_in_megabytes'}{'minimum'}" );
            },
        },
        'logchmod' => {
            needs_role => 'WebServer',
            'checkval' => sub {
                my $val = shift;

                return $val && $val =~ m{ \A [01] [0-7]{3} \z }xms
                  ? $val    #preserve initial zeros
                  : ( undef, "Value must be valid permissions set" );
            },
            'type'      => 'number',
            'maxlength' => 4,
        },
        'showwhmbwusageinmegs' => {
            'type' => 'binary',
        },
        'statsloglevel' => {
            'minimum'  => 1,
            'maximum'  => 10,
            'checkval' => sub {
                my $val = shift();

                return $val && $val =~ m{\A(\d+)\z} && $1 <= $Whostmgr::TweakSettings::Main::Conf{'statsloglevel'}{'maximum'}
                  ? int $1
                  : ( undef, "Value must be a numer below $Whostmgr::TweakSettings::Main::Conf{'statsloglevel'}{'maximum'}" );
            },
            'type'      => 'number',
            'maxlength' => '2',
        },
        'loadthreshold' => {
            'checkval'  => \&_is_positive_float,
            'can_undef' => 1,
            'type'      => 'number'
        },
        'alwaysredirecttossl' => {
            'type' => 'binary',
        },
        'logout_redirect_url' => {
            'default_text' => 'No redirection',
            'type'         => 'path',
        },
        'cpredirect' => {
            'type'     => 'radio',
            'options'  => [ 'Hostname', 'Origin Domain Name', ],
            'excludes' => 'alwaysredirecttossl',
        },
        'cpredirectssl' => {
            'type'     => 'radio',
            'options'  => [ 'SSL Certificate Name', 'Hostname', 'Origin Domain Name', ],
            'excludes' => 'alwaysredirecttossl',
        },
        'conserve_memory' => {
            'type'        => 'binary',
            'value'       => sub { return _current_system_value_for('conserve_memory') },
            'post_action' => sub {

                # cpconfguard unsafe
                my ( $val, $oldval, $force ) = @_;
                my $return = _set_touch_file( '/var/cpanel/conserve_memory', $val );

                if ( $force || !defined $oldval || $val ne $oldval ) {
                    _schedule_cpservices_task('restartsrv dovecot');
                }

                return $return;
            },
        },
        'selfsigned_generation_for_bestavailable_ssl_install' => {
            'type' => 'binary',
        },
        'allowcpsslinstall' => {
            needs_role    => 'UserSSL',
            'type'        => 'binary',
            'post_action' => \&_update_global_cache,
        },
        'apache_port' => {
            needs_role  => 'WebServer',
            'maxlength' => 21,
            'type'      => 'number',
            'checkval'  => sub {
                my $val = shift;

                return $val && $val =~ m{ \A (?:\d+\.\d+\.\d+\.\d+:\d+|\d+) \z }xms
                  ? $val
                  : ( undef, "Value must be in the format IP:PORT" );
            },
            'action' => sub {

                #cpanel.config guard safe
                my ( $val, $oldval, $force ) = @_;

                return 1 unless ( $force || !defined($oldval) || $val ne $oldval );
                return 1 if !Cpanel::Config::Httpd::EA4::is_ea4();
                eval { Cpanel::ServerTasks::queue_task( [ 'ApacheTasks', 'TailwatchTasks' ], 'build_apache_conf', 'userdata_update', 'apache_restart --force', 'reloadtailwatch' ); };
                if ($@) {
                    print $@;
                    return 0;
                }
                require Cpanel::SafeDir::MK;
                Cpanel::SafeDir::MK::safemkdir( '/var/cpanel/config/apache', 0755 ) if !-d '/var/cpanel/config/apache';

                if ( open( my $port_fh, '>', '/var/cpanel/config/apache/port' ) ) {
                    print {$port_fh} $val;
                    close($port_fh);
                }
                return 1;
            },
        },
        'apache_ssl_port' => {
            needs_role  => 'WebServer',
            'maxlength' => 21,
            'type'      => 'number',
            'checkval'  => sub {
                my $val = shift;

                return $val && $val =~ m{ \A (?:\d+\.\d+\.\d+\.\d+:\d+|\d+) \z }xms
                  ? $val
                  : ( undef, "Value must be in the format IP:PORT" );
            },
            'action' => sub {

                #cpanel.config guard safe
                my ( $val, $oldval, $force ) = @_;
                return 1 unless ( $force || !defined($oldval) || $val ne $oldval );
                return 1 if !Cpanel::Config::Httpd::EA4::is_ea4();
                eval { Cpanel::ServerTasks::queue_task( [ 'ApacheTasks', 'TailwatchTasks' ], 'build_apache_conf', 'userdata_update', 'apache_restart --force', 'reloadtailwatch' ); };
                if ($@) {
                    print $@;
                    return 0;
                }
                return 1;
            },
        },
        'api_shell' => {
            'type'        => 'binary',
            'post_action' => \&_clear_navigation_cache,
        },
        'allow_server_info_status_from' => {
            needs_role => 'WebServer',
            'type'     => 'textarea',
            'width'    => 15,
            'format'   => sub {
                my $val = shift();
                $val =~ s{[,;\s]+}{\n}g;

                return $val;
            },
            'checkval' => sub {
                my $val  = shift();
                my @list = split m{[,;\s]+}, Cpanel::StringFunc::Trim::ws_trim($val);
                my @fails;
                for my $value (@list) {
                    my $ok = _filter_allow_from_directive($value);
                    push( @fails, $value ) unless $ok;
                }
                if ( scalar @fails ) {
                    return ( undef, "The following are illegal values: " . join( " ", @fails ) );
                }
                return join( q{ }, @list );
            },
            'action' => sub {

                #cpanel.config guard safe

                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );
                return 1 if !Cpanel::Config::Httpd::EA4::is_ea4();
                eval { Cpanel::ServerTasks::queue_task( ['ApacheTasks'], 'build_apache_conf', 'apache_restart --force' ); };
                if ($@) {
                    print $@;
                    return 0;
                }
                return 1;
            },
        },
        'cpsrvd-domainlookup' => {
            'type' => 'binary',
        },
        'cpdavd_caldav_upload_limit' => {
            'minimum'  => 1,
            'default'  => 10,
            'type'     => 'number',
            'unit'     => 'MB',
            'width'    => 5,
            'label'    => 'Maximum size in MB per attachment upload',
            'help'     => 'The maximum size (in megabytes) allowed for attachments to calendar events. Default is 10.',
            'checkval' => \&_is_whole_number,
        },
        'repquota_timeout' => {
            'type'     => 'number',
            'unit'     => 's',
            'width'    => 3,
            'checkval' => \&_is_natural_number,
        },
        'disablequotacache' => {
            'type' => 'inversebinary',
        },
        'account_login_access' => {
            'type'    => 'radio',
            'options' => [ 'owner_root', 'owner', 'user', ],
        },
        'bind_deferred_restart_time' => {
            needs_role => 'DNS',
            'type'     => 'number',
            'unit'     => 's',
            'width'    => 4,
            'maximum'  => 300,
            default    => 2,
            'checkval' => \&_is_whole_number,
        },
        httpd_deferred_restart_time => {
            needs_role => 'WebServer',
            type       => 'number',
            unit       => 's',
            width      => 4,
            default    => 0,
            checkval   => \&_is_whole_number,
        },
        'dnslookuponconnect' => {
            'type' => 'binary',
        },
        'file_upload_max_bytes' => {
            'minimum'  => 1,
            'maximum'  => 10240,    #checked in Cpanel::Form
            'checkval' => sub {
                my $float = _is_float( $_[0] );

                return ( defined $float && $float >= $Whostmgr::TweakSettings::Main::Conf{'file_upload_max_bytes'}{'minimum'} && $float <= $Whostmgr::TweakSettings::Main::Conf{'file_upload_max_bytes'}{'maximum'} )
                  ? $float + 0      #get rid of extra 0s
                  : ( undef, "Value must be a float between $Whostmgr::TweakSettings::Main::Conf{'file_upload_max_bytes'}{'minimum'} and $Whostmgr::TweakSettings::Main::Conf{'file_upload_max_bytes'}{'maximum'}" );
            },
            'can_undef' => 1,
            'type'      => 'number',
            'unit'      => 'MB',
            'width'     => 9,
        },
        'file_upload_must_leave_bytes' => {
            'checkval' => \&_is_natural_number,
            'type'     => 'number',
            'unit'     => 'MB',
            'width'    => 9,
        },
        'jailprocmode' => {
            'type'    => 'radio',
            'options' => [ 'mount_proc_full', 'mount_proc_jailed_fallback_full', 'mount_proc_jailed_fallback_none' ],
            'value'   => sub {
                return 'mount_proc_full'                 if -e "/var/cpanel/conf/jail/flags/mount_proc_full";
                return 'mount_proc_jailed_fallback_none' if -e "/var/cpanel/conf/jail/flags/mount_proc_jailed_fallback_none";
                return 'mount_proc_jailed_fallback_full';
            },
            'action' => sub {

                #cpanel.config guard safe
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );

                require Cpanel::SafeDir::MK;
                Cpanel::SafeDir::MK::safemkdir( '/var/cpanel/conf/jail/flags', 0700 ) if !-e '/var/cpanel/conf/jail/flags';
                if ( $val eq 'mount_proc_full' ) {
                    unlink "/var/cpanel/conf/jail/flags/mount_proc_jailed_fallback_full";
                    unlink "/var/cpanel/conf/jail/flags/mount_proc_jailed_fallback_none";
                    _set_touch_file( "/var/cpanel/conf/jail/flags/mount_proc_full", 1 );
                }
                elsif ( $val eq 'mount_proc_jailed_fallback_none' ) {
                    unlink "/var/cpanel/conf/jail/flags/mount_proc_full";
                    unlink "/var/cpanel/conf/jail/flags/mount_proc_jailed_fallback_full";
                    _set_touch_file( "/var/cpanel/conf/jail/flags/mount_proc_jailed_fallback_none", 1 );
                }
                else {
                    # default to mount_proc_jailed_fallback_full
                    unlink "/var/cpanel/conf/jail/flags/mount_proc_full";
                    unlink "/var/cpanel/conf/jail/flags/mount_proc_jailed_fallback_none";
                    _set_touch_file( "/var/cpanel/conf/jail/flags/mount_proc_jailed_fallback_full", 1 );
                }

                return 1;
            },
        },
        'jailmountbinsuid' => {
            'type'  => 'binary',
            'value' => sub {
                return -e "/var/cpanel/conf/jail/flags/mount_bin_suid" ? 1 : 0;
            },
            'action' => sub {

                #cpanel.config guard safe
                my $val = shift;
                require Cpanel::SafeDir::MK;
                Cpanel::SafeDir::MK::safemkdir( '/var/cpanel/conf/jail/flags', 0700 ) if !-e '/var/cpanel/conf/jail/flags';

                return _set_touch_file( '/var/cpanel/conf/jail/flags/mount_bin_suid', $val );
            },
        },
        'jailmountusrbinsuid' => {
            'type'  => 'binary',
            'value' => sub {
                return -e "/var/cpanel/conf/jail/flags/mount_usr_bin_suid" ? 1 : 0;
            },
            'action' => sub {

                #cpanel.config guard safe
                my $val = shift;
                require Cpanel::SafeDir::MK;
                Cpanel::SafeDir::MK::safemkdir( '/var/cpanel/conf/jail/flags', 0700 ) if !-e '/var/cpanel/conf/jail/flags';

                return _set_touch_file( '/var/cpanel/conf/jail/flags/mount_usr_bin_suid', $val );
            },
        },
        'jaildefaultshell' => {
            'type' => 'binary',
        },
        'maxmem' => {
            'format'   => \&_format_unlimited,
            'checkval' => sub {
                my $val = shift;

                if ( $val eq 'unlimited' || $val == 0 ) {
                    return 0;
                }
                else {
                    return $val =~ m{\A\d+\z} && $val >= $Whostmgr::TweakSettings::Main::Conf{'maxmem'}{'minimum'}
                      ? int $val
                      : ( undef, "Value must be a whole positive integer larger than $Whostmgr::TweakSettings::Main::Conf{'maxmem'}{'minimum'}" );
                }
            },
            'can_undef' => 1,
            'minimum'   => Cpanel::Maxmem::default(),
            'type'      => 'number',
            'unit'      => 'MB',
            'width'     => 5,
        },
        'permit_appconfig_entries_without_acls' => {
            'type' => 'binary',
        },
        'permit_appconfig_entries_without_features' => {
            'type' => 'binary',
        },

        'permit_unregistered_apps_as_root' => {
            'type' => 'binary',
        },
        'permit_unregistered_apps_as_reseller' => {
            'type' => 'binary',
        },
        'disable-php-as-reseller-security' => {
            'type' => 'binary',
        },
        'maintenance_rpm_version_check' => {
            'type' => 'binary',
        },
        'maintenance_rpm_version_digest_check' => {
            'type'     => 'binary',
            'requires' => 'maintenance_rpm_version_check',
        },
        'skipnotifyacctbackupfailure' => {
            'type' => 'inversebinary',
        },
        'remotewhmtimeout' => {
            'minimum'  => 35,
            'width'    => 5,
            'type'     => 'number',
            'unit'     => 's',
            'checkval' => sub {
                my $val = shift;

                return $val && $val =~ m{ \A \d+ \z }xms && $val >= $Whostmgr::TweakSettings::Main::Conf{'remotewhmtimeout'}->{'minimum'}
                  ? int $val
                  : ( undef, "Value must be a positive integer greater than $Whostmgr::TweakSettings::Main::Conf{'remotewhmtimeout'}->{'minimum'}" );
            },
        },
        'nosendlangupdates' => {    # Do not remove. Required by "License to Language File Modifications" in cPanel & WebHost Manager EULA.
            'type' => 'inversebinary',
        },
        'invite_sub' => {
            'ui_default'  => 1,
            'type'        => 'binary',
            'post_action' => sub {
                my ( $current, $old ) = @_;
                if ( ( $old || 0 ) ne ( $current || 0 ) ) {
                    return _queue_cpsrvd_restart();
                }
                return 1;
            }

        },
        'resetpass' => {
            'ui_default'  => 1,
            'type'        => 'binary',
            'post_action' => sub {
                my ( $current, $old ) = @_;
                if ( ( $old || 0 ) ne ( $current || 0 ) ) {
                    my $cachedir = '/var/cpanel/caches/showtemplate.stor';
                    foreach ( glob("$cachedir/login_template_*") ) {
                        unlink $_;
                    }
                    return _queue_cpsrvd_restart();
                }
                return 1;
            }

        },
        'resetpass_sub' => {
            'ui_default'  => 1,
            'type'        => 'binary',
            'post_action' => sub {
                my ( $current, $old ) = @_;
                if ( ( $old || 0 ) ne ( $current || 0 ) ) {
                    my $cachedir = '/var/cpanel/caches/showtemplate.stor';
                    foreach ( glob("$cachedir/login_template_*") ) {
                        unlink $_;
                    }
                    return _queue_cpsrvd_restart();
                }
                return 1;
            }

        },
        'skipparentcheck' => {
            'type'   => 'binary',
            'value'  => sub { return -e '/var/cpanel/skipparentcheck' ? 1 : 0; },
            'action' => sub {

                #cpanel.config guard safe
                my ($val) = @_;
                return _set_touch_file( '/var/cpanel/skipparentcheck', $val );
            },
        },
        'htaccess_check_recurse' => {
            needs_role => 'WebServer',
            'minimum'  => 0,
            'checkval' => sub {
                my $val = shift;

                return defined $val && $val =~ m{ \A \d+ \z }xms && $val >= $Whostmgr::TweakSettings::Main::Conf{'htaccess_check_recurse'}{'minimum'}
                  ? int $val
                  : ( undef, "Value must be a positive integer greater thqn $Whostmgr::TweakSettings::Main::Conf{'htaccess_check_recurse'}{'minimum'}" );
            },
            'type'      => 'number',
            'maxlength' => '3',
        },
        'min_time_between_apache_graceful_restarts' => {
            needs_role => 'WebServer',
            'checkval' => \&_is_natural_number,
            'maximum'  => 600,
            'minimum'  => 10,
            'default'  => 10,
            'type'     => 'number',
        },

        'tcp_check_failure_threshold' => {
            'checkval'  => \&_is_natural_number,
            'can_undef' => 1,
            'type'      => 'number',
            'action'    => sub {

                #cpanel.config guard safe

                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );

                eval { Cpanel::ServerTasks::queue_task( ['TailwatchTasks'], 'reloadtailwatch' ); };
                if ($@) {
                    print $@;
                    return 0;
                }
                return 1;
            },
        },
        'dnsadmin_verbose_sync' => {
            'type' => 'binary',
        },
        'dnsadmin_log' => {
            'type'    => 'number',
            'minimum' => 0,
            'maximum' => 9,
        },
        'maxcpsrvdconnections' => {
            'checkval' => \&_is_natural_number,
            'maximum'  => 16384,
            'minimum'  => 200,
            'type'     => 'number',
        },
        'ftpquotacheck_expire_time' => {
            needs_role => 'FileStorage',
            'checkval' => \&_is_positive_float,
            'maximum'  => 365000,
            'minimum'  => 1,
            'type'     => 'number',
        },
        'ionice_dovecot_maintenance' => {
            'checkval'      => \&_is_whole_number,
            'maximum'       => 7,
            'minimum'       => 0,
            'type'          => 'number',
            'requires_test' => [ -x Cpanel::Binaries::path('ionice') || '', '==', 1 ],
        },
        'ionice_email_archive_maintenance' => {
            needs_role      => 'MailReceive',
            'checkval'      => \&_is_whole_number,
            'maximum'       => 7,
            'minimum'       => 0,
            'type'          => 'number',
            'requires_test' => [ -x Cpanel::Binaries::path('ionice') || '', '==', 1 ],
            'includes'      => 'emailarchive',
        },
        'ionice_quotacheck' => {
            'checkval'      => \&_is_whole_number,
            'maximum'       => 7,
            'minimum'       => 0,
            'type'          => 'number',
            'requires_test' => [ -x Cpanel::Binaries::path('ionice') || '', '==', 1 ]
        },
        'ionice_ftpquotacheck' => {
            needs_role      => 'FileStorage',
            'checkval'      => \&_is_whole_number,
            'maximum'       => 7,
            'minimum'       => 0,
            'type'          => 'number',
            'requires_test' => [ -x Cpanel::Binaries::path('ionice') || '', '==', 1 ]
        },
        'ionice_bandwidth_processing' => {
            'checkval'      => \&_is_whole_number,
            'maximum'       => 7,
            'minimum'       => 0,
            'type'          => 'number',
            'requires_test' => [ -x Cpanel::Binaries::path('ionice') || '', '==', 1 ]
        },
        'ionice_log_processing' => {
            'checkval'      => \&_is_whole_number,
            'maximum'       => 7,
            'minimum'       => 0,
            'type'          => 'number',
            'requires_test' => [ -x Cpanel::Binaries::path('ionice') || '', '==', 1 ]
        },
        'ionice_cpbackup' => {
            'checkval'      => \&_is_whole_number,
            'maximum'       => 7,
            'minimum'       => 0,
            'type'          => 'number',
            'requires_test' => [ -x Cpanel::Binaries::path('ionice') || '', '==', 1 ]
        },
        'ionice_userbackup' => {
            'checkval'      => \&_is_whole_number,
            'maximum'       => 7,
            'minimum'       => 0,
            'type'          => 'number',
            'requires_test' => [ -x Cpanel::Binaries::path('ionice') || '', '==', 1 ]
        },
        'ionice_userproc' => {
            'checkval'      => \&_is_whole_number,
            'maximum'       => 7,
            'minimum'       => 0,
            'type'          => 'number',
            'requires_test' => [ -x Cpanel::Binaries::path('ionice') || '', '==', 1 ]
        },
        'server_locale' => {
            type    => 'locale',
            label   => 'Server Locale',
            help    => 'The locale that the system will use when the user’s locale is unavailable. Set this to the locale that administrators, resellers, and users are most likely to understand.',
            'value' => sub {
                require Cpanel::LoadFile;
                require Cpanel::Locale;
                return Cpanel::LoadFile::load_if_exists($Cpanel::Locale::SERVER_LOCALE_FILE);
            },
            'post_action' => sub {
                my ( $val, $oldval, $force ) = @_;
                return 1 if ( !$force && $val eq $oldval );

                require Cpanel::Locale;
                Cpanel::FileUtils::Write::overwrite( $Cpanel::Locale::SERVER_LOCALE_FILE, $val, 0644 );

                # Force cpsrvd to reload CPCONF
                eval { Cpanel::ServerTasks::queue_task( ['CpServicesTasks'], 'hupcpsrvd' ); };
                if ($@) {
                    print $@;
                    return 0;
                }
                return 1;
            },
        },
        'create_account_dkim' => {
            needs_role => 'MailReceive',
            'type'     => 'binary',
            'label'    => 'Enable <acronym title="DomainKeys Identified Mail">DKIM</acronym> on domains for newly created accounts',
        },
        'create_account_spf' => {
            needs_role => 'MailReceive',
            'type'     => 'binary',
            'label'    => 'Enable <acronym title="Sender Policy Framework">SPF</acronym> on domains for newly created accounts',
        },
        'skip_chkservd_recovery_notify' => {
            'type'  => 'inversebinary',
            'label' => 'Enable ChkServd recovery notifications',
        },
        'chkservd_plaintext_notify' => {
            'type'  => 'inversebinary',
            'label' => 'Enable ChkServd HTML notifications',
        },
        'exim_retention_days' => {
            'checkval' => \&_is_positive_float,
            'maximum'  => 365_000,
            'minimum'  => 1,
            'type'     => 'number',
            'label'    => 'Retention interval for Exim stats in the database, in days',
        },
        'modsec_keep_hits' => {
            needs_role => 'WebServer',
            'checkval' => \&_is_whole_number,
            'type'     => 'number',
            'label'    => 'Retention interval for ModSecurity™ rule hit records, in days',
        },
        'chkservd_check_interval' => {
            'checkval' => \&_is_positive_float,
            'maximum'  => 7200,
            'minimum'  => 60,
            'type'     => 'number',
            'label'    => 'The number of seconds between ChkServd service checks.',
            'action'   => sub {
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;
                return 1 if ( !$force && $val eq $oldval );

                eval { Cpanel::ServerTasks::queue_task( ['TailwatchTasks'], 'reloadtailwatch' ); };
                if ($@) {
                    print $@;
                    return 0;
                }
                return 1;
            },
        },
        'chkservd_hang_allowed_intervals' => {
            'checkval' => \&_is_positive_float,
            'maximum'  => 20,
            'minimum'  => 1,
            'type'     => 'number',
            'label'    => 'The number of cycles ChkServd will wait for a previous check to complete before it terminates the check.',
        },
        'send_error_reports' => {
            'type' => 'binary',
        },
        'update_log_analysis_retention_length' => {
            'can_undef' => 1,
            'checkval'  => \&_is_whole_number,
            'options'   => [ 0, 90, undef ],
            'minimum'   => 0,
            'type'      => 'number',
            'unit'      => 'days',
        },
        'transfers_timeout' => {
            'can_undef' => 0,
            'checkval'  => \&_is_whole_number,
            'default'   => 1800,                                                                                                    # 15 min
            'minimum'   => 1800,                                                                                                    # 15 min
            'maximum'   => 172800,                                                                                                  # days
            'type'      => 'number',
            'unit'      => 'seconds',
            'label'     => 'Number of seconds an SSH connection related to an account transfer may be inactive before timing out'
        },
        'allow_login_autocomplete' => {
            type   => 'binary',
            label  => 'Allow autocomplete for login screens.',
            help   => 'This feature allows users to enable browser-native password caching for cPanel, WHM, and webmail logins. If you turn this off, it will not affect legacy-style (I.e. pre-11.32) login themes.',
            action =>                                                                                                                                                                                                    #cpanel.config guard safe

              sub { return 1; }
        },
        'enablecompileroptimizations' => {
            'type'   => 'binary',
            'value'  => sub { return -e _compileroptimize() ? 1 : 0; },
            'action' => sub {
                my ($val) = @_;

                return _set_touch_file( _compileroptimize(), $val );
            },
        },
        'gzip_compression_level' => {
            'checkval' => \&_is_whole_number,
            'default'  => 6,
            'minimum'  => 1,
            'maximum'  => 9,
            'type'     => 'number',
            'label'    => 'gzip compression level',
            'help'     => 'The level of compression to use (1 is faster but less compression, 9 is slower but provides maximum compression)',
        },
        'gzip_pigz_processes' => {
            'checkval' => \&_is_whole_number,
            'default'  => 1,
            'minimum'  => 1,
            'maximum'  => 128,
            'type'     => 'number',
            'label'    => 'Number of pigz processes',
            'help'     => 'The number of independent pigz processes to use when performing gzip compression.  For quickest compression, specify the same number of cores available on your server.',
        },
        'gzip_pigz_block_size' => {
            'checkval' => \&_is_whole_number,
            'minimum'  => 128,
            'default'  => 4096,
            'maximum'  => 524288,
            'type'     => 'number',
            'label'    => 'Number of kilobyte chunks per pigz compression work unit',
            'help'     => 'The size (in 1024 byte chunks) of compression work units to be distributed to each pigz process.  Default is 4096.  Systems with larger L2/L3 caches may benefit from higher values.',
        },

        'database_prefix' => {    ## XXX TODO
            type    => 'binary',
            default => 1,
            label   => 'Require a username prefix on names of new databases and database users',
            help    => sub {
                my $prefix_length = Cpanel::DB::Prefix::get_prefix_length();
                my $prefix_str    = ( $prefix_length == 8 ) ? 'the first eight characters of ' : '';
                return
                    'When this option is enabled, the system will require that the name of each new database or database user from a cPanel session begin with '
                  . $prefix_str
                  . 'the system username and an underscore (_). This makes it easier to tell which user owns a given database, but it also restricts the number of characters that users can use for names of databases and database users. Note that if the username changes at a later point, the name of the database or database user does NOT change. Also, while older cPanel API calls automatically add this prefix, newer API calls expect the caller to add it.';
            },
        },
        'force_short_prefix' => {
            type       => 'binary',
            'requires' => 'database_prefix',
            'ignoreif' => sub { return !$_[0]->{'database_prefix'} },
        },
        'signature_validation' => {
            type    => 'radio',
            options => [ 'Off', 'Release Keyring Only', 'Release and Development Keyrings' ],
            action  => sub {
                my $val    = shift;
                my $oldval = shift;
                my $force  = shift;

                return 1 if ( !$force && $val eq $oldval );

                if ( $val ne 'Off' ) {
                    Cpanel::LoadModule::load_perl_module('Cpanel::Crypt::GPG::VendorKeys');
                    Cpanel::Crypt::GPG::VendorKeys::download_public_keys();
                }

                return 1;
            },
        },
        'verify_3rdparty_cpaddons' => {
            type    => 'binary',
            default => 0,
        },
        'upcp_log_retention_days' => {
            'checkval' => \&_is_whole_number,
            'minimum'  => 3,
            'default'  => 45,
            'maximum'  => 999,
            'type'     => 'number',
            'label'    => 'Number of days to retain upcp logs before purging them',
            'help'     => 'These files can be found in the /var/cpanel/updatelogs directory.',
        },
        'log_successful_logins' => {
            type => 'binary',
        },
        'userdirprotect' => {
            'ui_default' => 1,
            'type'       => 'binary',
            'default'    => 1,
            'action'     => sub {
                Cpanel::LoadModule::load_perl_module('Whostmgr::TweakSettings::Main::Setting::userdirprotect');
                return Whostmgr::TweakSettings::Main::Setting::userdirprotect::action(@_);
            },
        },
        enablefileprotect => {
            needs_role => 'WebServer',
            type       => 'binary',
            default    => 1,

            # This must be a post action so the scripts we call below don't
            # contend on the cpanel.config lock.
            post_action => sub {
                my ( $val, $oldval ) = @_;

                # immediate success (1) (i.e., do nothing) if disabled
                # or no change in value
                return 1 if 2 == grep { defined } ( $val, $oldval ) and $val == $oldval;

                # return success if system call is successful
                return 0 == system '/usr/local/cpanel/scripts/' . (qw(disablefileprotect enablefileprotect))[ !!$val ];
            },
            'value' => sub {
                return _current_system_value_for('enablefileprotect');
            }
        },
        allow_deprecated_accesshash => {
            type        => 'binary',
            post_action => \&_clear_navigation_cache,
        },
        'rpmup_allow_kernel' => {
            'type' => 'binary',
        },
        display_cpanel_doclinks => {
            type          => 'binary',
            'post_action' => \&_update_global_cache,
        },
        display_cpanel_promotions => {
            'default'     => 1,
            'type'        => 'binary',
            'post_action' => \&_update_global_cache,
        },
        default_pkg_max_emailacct_quota => {
            needs_role => 'MailReceive',
            'checkval' => \&_is_natural_number,
            'maximum'  => Cpanel::Email::Maildir::get_max_email_quota_mib(),
            'default'  => $cpconf_defaults_hr->{default_pkg_max_emailacct_quota},
            'type'     => 'number',
            'unit'     => 'MB',
            'width'    => 7,
        },
        default_pkg_quota => {
            'checkval' => \&_is_natural_number,
            'default'  => $cpconf_defaults_hr->{default_pkg_quota},
            'type'     => 'number',
            'unit'     => 'MB',
            'width'    => 7,
        },
        default_pkg_bwlimit => {
            'checkval' => \&_is_natural_number,
            'default'  => $cpconf_defaults_hr->{default_pkg_bwlimit},
            'type'     => 'number',
            'unit'     => 'MB',
            'width'    => 7,
        },
        enable_piped_logs => {
            type  => 'binary',
            value => sub {
                my ($cpconf) = @_;
                Cpanel::Debug::log_warn("cpconf was not provided to enable_piped_logs value") if !$cpconf;
                $cpconf ||= Cpanel::Config::CpConfGuard->new( use_lock => 0 )->{'data'};
                return $cpconf->{'enable_piped_logs'} if defined $cpconf->{'enable_piped_logs'};
                return;
            },
            post_action => \&_rebuild_httpconf,
        },
        show_reboot_banner => {
            'type' => 'binary',
        },
        csp => {
            'type' => 'binary',
        },
        'skipfirewall' => {
            'type' => 'binary',
        },
        'skip_rules_added_by_configure_firewall_for_cpanel' => {
            'type' => 'binary',
        },
        'enforce_user_account_limits' => {
            'type' => 'binary',
        },
        'copy_default_error_documents' => {
            'type' => 'binary',
        },
        'enable_api_log' => {
            type => 'binary',
        },
    );

    if ($IPv6) {

        $Conf{'ipv6_control'} = {
            'type'   => 'binary',
            'action' => sub {

                #cpanel.config guard safe
                my ($val) = @_;
                return _set_touch_file( '/var/cpanel/ipv6_control', $val );
            },
            'value' => sub { return -e '/var/cpanel/ipv6_control' ? 1 : 0; },
        };

    }

    if ( !_skip_if_cpaddons_disabled() ) {

        $Conf{'cpaddons_adminemail'} = {
            'skipif'       => \&_skip_if_cpaddons_disabled,
            'default_text' => 'None',
            'type'         => 'path',
        };
        $Conf{'cpaddons_max_moderation_req_all_mod'} = {
            'skipif'   => \&_skip_if_cpaddons_disabled,
            'checkval' => \&_is_natural_number,
            'type'     => 'number'
        };
        $Conf{'cpaddons_max_moderation_req_per_mod'} = {
            'skipif'   => \&_skip_if_cpaddons_disabled,
            'checkval' => \&_is_natural_number,
            'type'     => 'number'
        };
        $Conf{'cpaddons_moderation_request'} = {
            'skipif' => \&_skip_if_cpaddons_disabled,
            'type'   => 'binary',
        };
        $Conf{'cpaddons_no_3rd_party'} = {
            'skipif' => \&_skip_if_cpaddons_disabled,
            'type'   => 'inversebinary',
        };
        $Conf{'cpaddons_no_modified_cpanel'} = {
            'skipif' => \&_skip_if_cpaddons_disabled,
            'type'   => 'inversebinary',
        };
        $Conf{'cpaddons_autoupdate'} = {
            'skipif' => \&_skip_if_cpaddons_disabled,
            'type'   => 'binary',
        };
        $Conf{'cpaddons_notify_owner'} = {
            'skipif' => \&_skip_if_cpaddons_disabled,
            'type'   => 'binary',
        };
        $Conf{'cpaddons_notify_root'} = {
            'skipif' => \&_skip_if_cpaddons_disabled,
            'type'   => 'binary',
        };
        $Conf{'cpaddons_notify_users'} = {
            'skipif'  => \&_skip_if_cpaddons_disabled,
            'type'    => 'radio',
            'options' => [ 'Allow users to choose', 'always', 'never', ],
        };
    }

    return;
}    # _init_vars

sub _skip_if_cpaddons_disabled {
    return 1 unless Cpanel::OS::supports_cpaddons();
    return 1 if -e q[/var/cpanel/cpaddons.disabled];
    return 0;
}

## CPANEL-11095: Apache's "Allow from" directive is an odd one, because it
## allows for partial domain names and partial IP address (both v4 and v6), with
## an additional optional complexity of a network portion. It would be
## inappropriate to apply an actual IP validator in this case. For now, this filter
## spells out that 'all' is acceptable, and v4 and v6 equivalents of intending
## the same are not legal.
sub _filter_allow_from_directive {
    my ($value) = @_;
    if ( $value eq 'all' ) {
        return 1;
    }

    ## Explicitly disallow IPv6 values intended as equivalent to 'all'
    if ( ( $value eq '::' ) or ( $value =~ m!^\[::\]! ) ) {
        return;
    }

    ## Explicitly disallow IPv4 values intended as equivalent to 'all'
    if ( ( $value eq '/0' ) or ( $value =~ m/^0(?:\.0)*/ ) ) {
        return;
    }

    ## Explicitly disallow trailing colons (CPANEL-38920)
    if ( $value =~ /\d:$/a || $value =~ /^:$/ ) {
        return;
    }

    ## Explicitly disallow configuration directives
    if ( $value =~ /[\<\>]/ ) {
        return;
    }

    return 1;
}

sub set_local_versions_target {
    my ( $enabled, $target, $target_key_file ) = @_;

    # TODO: Use Cpanel::RPM::Versions::File here intead of a /usr/local/cpanel/scripts/update_local_rpm_versions
    # Assume the target defaults to installed.
    if ($enabled) {
        _system( qw{/usr/local/cpanel/scripts/update_local_rpm_versions --del }, "target_settings.$target" );
        return if ( -e $target_key_file );
    }
    else {
        _system( qw{/usr/local/cpanel/scripts/update_local_rpm_versions --edit}, "target_settings.$target", 'uninstalled' );
        return if ( !-e $target_key_file );
    }

    # Stop here and do not reinstall rpms on a base install
    # as this will be done at upcp time
    return if $ENV{'CPANEL_BASE_INSTALL'};
    _system( qw{/usr/local/cpanel/scripts/check_cpanel_pkgs --fix --long-list --no-digest}, "--targets=$target" );
    return;
}

# for mocking
sub _system {
    my (@cmd) = @_;
    return system(@cmd);
}

{
    my $default;

    sub _get_etc_cpanel_config_value_for {
        my $key = shift;
        return unless $key;

        $default ||= Cpanel::Config::CpConfGuard::Default->new();
        return $default->get_static_default_for($key);
    }

    # This relies on there being a dynamic calculator which will
    # look out in the system and determine it's current state.
    # It SHOULD NOT be used in this module to determine 'default'
    sub _current_system_value_for {
        my $key = shift;
        return unless $key;

        $default ||= Cpanel::Config::CpConfGuard::Default->new();
        return $default->get_dynamic_key($key);
    }

}

sub set_defaults {
    foreach my $name ( sort keys %Conf ) {
        next if ( $Conf{$name}->{default} );

        $Conf{$name}->{default} = _get_etc_cpanel_config_value_for($name);    # || $Conf{$name}->{default};
    }

    return;
}

sub _compileroptimize { return '/var/cpanel/compileroptimize' }

sub _save_proxysubdomains_old_autodiscover_host_for_post_action {
    my $cpconf = shift;
    $cpconf ||= Cpanel::Config::CpConfGuard->new( use_lock => 0 )->{'data'};
    if ( defined $cpconf->{'autodiscover_host'} ) {
        return $PROXY_SUBDOMAINS_OLD_AUTODISCOVER_HOST = $cpconf->{'autodiscover_host'};
    }
    return;
}

sub _queue_mysql_restart {
    return _schedule_cpservices_task('restartsrv mysql');
}

sub _queue_cpsrvd_restart {
    return _schedule_cpservices_task('restartsrv cpsrvd');
}

sub _schedule_cpservices_task {
    my ($task_str) = @_;
    my $err;
    try {
        Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 5, $task_str );
    }
    catch {
        $err = $_;
    };
    if ($err) {
        print Cpanel::Exception::get_string($err) . "\n";
        return 0;
    }
    return 1;
}

sub _set_touch_file {
    my ( $file, $value ) = @_;
    $file or die;

    if ($value) {
        if ( !-e $file && open( my $fh, '>', $file ) ) {
            close $fh;
        }
        return ( -e $file ) ? 1 : 0;
    }
    else {
        unlink $file;
        return ( -e $file ) ? 0 : 1;
    }
}

sub _solo_license {
    return 1 == Cpanel::Server::Type::get_max_users();
}

sub _update_global_cache {
    return Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 5, 'build_global_cache' );
}

sub _clear_navigation_cache {
    my ( $val, $oldval ) = @_;
    if ( $val ne $oldval ) {
        Whostmgr::Templates::Chrome::Rebuild::rebuild_whm_chrome_cache();
    }

    return;
}

sub _rebuild_httpconf {
    my ( $val, $oldval ) = @_;

    require Cpanel::SafeRun::Errors;

    if ( $val ne $oldval && -x '/usr/local/cpanel/bin/splitlogs' && Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/bin/splitlogs', '--bincheck' ) =~ /BinCheck Ok/ ) {
        require Cpanel::Kill;

        # Whostmgr::TweakSettings::set_value() expects you to have altered the cpanel.config
        # before being invoked... to simply the featureshowcase implementation for pipe logging
        # just do this as part of the post_action
        require Cpanel::Config::CpConfGuard;
        my $cpconf = Cpanel::Config::CpConfGuard->new();
        $cpconf->{'data'}->{'enable_piped_logs'} = $val;
        $cpconf->save();

        eval {
            Cpanel::ServerTasks::queue_task( ['ApacheTasks'], 'build_apache_conf', 'apache_restart --force' );
            Cpanel::Kill::killall( 'HUP', 'cpanellogd' );
        };
    }
    return;
}

sub _checkphpini_and_install_php_inis {
    local $@;
    eval { Cpanel::ServerTasks::schedule_task( ['PHPTasks'], 3, 'checkphpini_and_install_php_inis' ); 1; };
    warn if $@;
    return;
}
1;
__END__

=pod

=head1 NAME

Whostmgr::TweakSettings::Main - The main tweaksettings configuration.
