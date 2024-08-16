package Cpanel::AdvConfig::dovecot;

# cpanel - Cpanel/AdvConfig/dovecot.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Try::Tiny;

use Cpanel::Config::Hulk                  ();
use Cpanel::ConfigFiles                   ();
use Cpanel::SafeRun::Errors               ();
use Cpanel::SafeDir::MK                   ();
use Cpanel::AdvConfig                     ();
use Cpanel::Debug                         ();
use Cpanel::Dovecot                       ();
use Cpanel::Dovecot::Compat               ();
use Cpanel::Dovecot::Constants            ();
use Cpanel::Dovecot::Solr                 ();
use Cpanel::Dovecot::IncludeTrashInQuota  ();
use Cpanel::AdvConfig::dovecot::utils     ();
use Cpanel::AdvConfig::dovecot::Imunify   ();
use Cpanel::LoadModule                    ();
use Cpanel::AdvConfig::dovecot::Constants ();
use Cpanel::FileUtils::Lines              ();
use Cpanel::FileUtils::Copy               ();
use Cpanel::CPAN::Hash::Merge             ();
use Cpanel::IPv6::Has                     ();
use Cpanel::SSL::Defaults                 ();
use Cpanel::Rand::Get                     ();
use Cpanel::FileUtils::Write              ();
use Cpanel::Template::Files               ();
use Cpanel::Time::ISO                     ();
use Cpanel::Context                       ();
use Cpanel::Hulk::Key                     ();
use Cpanel::APNS::Mail::Config            ();
use Cpanel::Services::Enabled             ();
use Cpanel::ServerTasks                   ();
use Cpanel::OS                            ();

our $VERSION = '2.0';

our $_TEMPLATES_SOURCE_DIR = "$Cpanel::ConfigFiles::CPANEL_ROOT/src/templates";
our $_TEMPLATES_TARGET_DIR = '/var/cpanel/templates';

my $service = 'dovecot';

our @ssl_protocol_order = qw/SSLv2 SSLv3 TLSv1 TLSv1.1 TLSv1.2/;

our $validate_map = {
    'mail_process_size'       => '^[0-9]{2,7}$',                                           # qr// is too expensive here
    'mdbox_rotate_interval'   => '^(0|[1-7][0-9]{0,2}[01]{0,1}w|[0-4][0-9]{0,3}0*d$)$',    # Accepts 0, or up to 49710d/7101w
    'mdbox_rotate_size'       => '^[0-9]{1,3}M$',                                          # qr// is too expensive here
    'auth_cache_size'         => '^[0-9]{1,3}M$',                                          # qr// is too expensive here
    'imap_hibernate_timeout'  => '^[0-9]{1,4}$',                                           # qr// is too expensive here
    'compress_messages'       => '^[01]$',                                                 # qr// is too expensive here
    'compress_messages_level' => '^[1-9]$',                                                # qr// is too expensive here
    'include_trash_in_quota'  => '^[01]$',
    'verbose_proctitle'       => '^(?:yes|no)$',
    'lmtp_process_min_avail'  => '^[0-9]{0,2}$',                                           # qr// is too expensive here
    'lmtp_process_limit'      => '^[1-9][0-9]{0,3}$',                                      # qr// is too expensive here
    'config_vsz_limit'        => '^[1-9][0-9]{2,4}$',                                      # qr// is too expensive here
};

# Defaults
my $soft_defaults = {
    'protocols'                      => 'imap pop3',
    'login_dir'                      => '/var/run/dovecot/login',
    'login_process_per_connection'   => 'no',
    'login_processes_count'          => 2,
    'ssl_cipher_list'                => Cpanel::SSL::Defaults::default_cipher_list(),
    'ssl_min_protocol'               => Cpanel::SSL::Defaults::default_ssl_min_protocol(),
    'ssl_cert_file'                  => '/etc/dovecot/ssl/dovecot.crt',
    'ssl_key_file'                   => '/etc/dovecot/ssl/dovecot.key',
    'maildir_very_dirty_syncs'       => 'yes',
    'maildir_broken_filename_sizes'  => 'yes',
    'maildir_copy_with_hardlinks'    => 'yes',
    'maildir_copy_preserve_filename' => 'yes',
    'include_trash_in_quota'         => '0',
    'incoming_reached_quota'         => 'bounce',                                                              #cf. Exim “quotadiscard”
    'disable_plaintext_auth'         => 'no',
    'login_max_processes_count'      => '50',
    'max_mail_processes'             => '512',
    'mdbox_rotate_interval'          => '0',
    'mdbox_rotate_size'              => '10M',
    'compress_messages_level'        => 6,
    'compress_messages'              => 0,
    'login_process_size'             => Cpanel::AdvConfig::dovecot::Constants::MINIMUM_LOGIN_PROCESS_SIZE(),
    'mail_process_size'              => Cpanel::AdvConfig::dovecot::Constants::MINIMUM_MAIL_PROCESS_SIZE(),
    'config_vsz_limit'               => '2048',
    'lmtp_process_limit'             => '500',
    'lmtp_process_min_avail'         => '0',
    'lmtp_user_concurrency_limit'    => 4,
    'login_max_connections'          => '500',
    'mailbox_idle_check_interval'    => '30',
    'verbose_proctitle'              => 'no',
    'first_valid_uid'                => undef,                                                                 # filled in later
    'imap_hibernate_timeout'         => '30',
    'protocol_imap'                  => {
        'mail_plugins'                => 'acl quota imap_quota',
        'mail_max_userip_connections' => '20',
        'imap_capability'             => '+NAMESPACE',
        'imap_idle_notify_interval'   => '24',                                                                 # See http://peterkieser.com/2011/03/25/androids-k-9-mail-battery-life-and-dovecots-push-imap/
        'imap_logout_format'          => 'in=%i, out=%o, bytes=%i/%o'
    },
    'protocol_pop3' => {
        'mail_plugins'                => 'quota',
        'mail_max_userip_connections' => '3',
        'pop3_uidl_format'            => 'UID%u-%v',
        'pop3_logout_format'          => 'in=%i, out=%o, top=%t/%p, retr=%r/%b, del=%d/%m, size=%s, bytes=%i/%o'

    },
    'namespace_private' => {
        'prefix'    => 'INBOX.',
        'inbox'     => 'yes',
        'separator' => '.',
    },
    'plugin' => {
        'acl'   => Cpanel::AdvConfig::dovecot::Constants::DEFAULT_PLUGIN_ACL(),
        'quota' => 'maildir',
    },
    'auth_cache_size'         => Cpanel::AdvConfig::dovecot::Constants::DEFAULT_AUTH_CACHE_SIZE(),
    'auth_cache_ttl'          => 3600,
    'auth_cache_negative_ttl' => 3600,
    'expire_trash'            => 0,
    'expire_trash_ttl'        => 30,
    'expire_spam'             => 0,
    'expire_spam_ttl'         => 30,
    'listen'                  => '*,::',
    'ssl_listen'              => '*,::',
    'ipv6'                    => 1,
};

my $conf = {};

sub get_config {
    my $args_ref = shift;

    # There's caching going on all over the place, so reset every global
    if ( exists $args_ref->{'reload'} && $args_ref->{'reload'} ) {
        $conf = {};
    }

    if ( !$conf->{'_initialized'} ) {
        _setup_soft_defaults();

        $conf = Cpanel::CPAN::Hash::Merge::merge( $conf, $soft_defaults );

        my $local_conf = Cpanel::AdvConfig::load_app_conf($service);
        if ( $local_conf && ref $local_conf eq 'HASH' ) {    # Had local configuration
            _initialize_ssl_min_protocol_from_ssl_protocols_if_needed($local_conf);    #left in place as a transitional feature
            $conf = Cpanel::CPAN::Hash::Merge::merge( $conf, $local_conf );
        }

        my $ipv6 = Cpanel::IPv6::Has::system_has_ipv6();

        # Remove IPv6 from the listen directives if ipv6 was turned off in the local
        # config or if the system doesn't support it.
        if ( !$ipv6 || !$conf->{'ipv6'} || $conf->{'ipv6'} eq '0' ) {
            $conf->{'listen'}     = '*';
            $conf->{'ssl_listen'} = '*';
        }

        # Cpanel::Hulk::Key::cached_fetch_key('dovecot'), will die if the keys file is missing.
        if ( !-e '/var/cpanel/cphulkd/keys/dovecot' && -x '/usr/local/cpanel/bin/hulkdsetup' && $> == 0 ) {
            Cpanel::SafeRun::Errors::saferunallerrors(q[/usr/local/cpanel/bin/hulkdsetup]);
        }

        # Moved hard_defaults into get_config so it is not run every time this module is loaded
        # since it has to fork+exec
        my $hard_defaults = {
            '_target_conf_file'           => Cpanel::AdvConfig::dovecot::utils::find_dovecot_conf(),
            'version'                     => Cpanel::AdvConfig::dovecot::utils::get_dovecot_version(),
            'binary'                      => Cpanel::AdvConfig::dovecot::utils::find_dovecot_bin(),
            'allow_domainowner_mail_pass' => _allow_domainowner_mail_pass(),
            'hulk_auth_passwd'            => Cpanel::Hulk::Key::cached_fetch_key('dovecot'),
            'hulk_enabled'                => Cpanel::Config::Hulk::is_enabled() ? 1 : 0,
            'auth_policy_hash_nonce'      => _auth_policy_hash_nonce(),
            'ssl_dh_file'                 => ( -e "/etc/dovecot/dh.pem" ? "/etc/dovecot/dh.pem" : "" ),

        };

        if ( Cpanel::Dovecot::Solr::is_installed() && Cpanel::Services::Enabled::is_enabled('cpanel-dovecot-solr') ) {
            $hard_defaults->{'fts_support'} = 1;
        }

        _augment_hard_defaults_with_xaps_topic_if_available($hard_defaults);

        $conf = Cpanel::CPAN::Hash::Merge::merge( $conf, $hard_defaults );

        if ( $args_ref->{'opts'}{'values_to_change'} ) {

            $conf = Cpanel::CPAN::Hash::Merge::merge( $conf, $args_ref->{'opts'}{'values_to_change'} );
        }

        _make_config_version_compat($conf);

        $conf->{'_initialized'} = 1;
    }

    #The 1 here indicates $needs_update to the dispatch layer. It appears
    #that this was put here intending to communicate $ok, however, rather
    #than $needs_update; i.e., it’s a mistake, but all it means is that we
    #run update_templates() every time. As it happens, as of 11.58 (COBRA-3140)
    #this is actually what we want since update_templates() now checks for
    #validity as well as doing simple mtime checks.
    return wantarray ? ( 1, $conf ) : $conf;
}

sub _make_config_version_compat {

    return;
}

sub get_defaults {

    # Send back a copy
    my $conf = {};
    _setup_soft_defaults();
    $conf = Cpanel::CPAN::Hash::Merge::merge( $conf, $soft_defaults );
    if ( Cpanel::Dovecot::Compat::has_ssl_min_protocol() ) {
        $conf->{'ssl_min_protocol'} = Cpanel::SSL::Defaults::default_ssl_min_protocol();
    }
    return $conf;
}

sub save_config {
    my %save_conf = %{$conf};
    delete $save_conf{'_initialized'};
    process_config_changes( \%save_conf );
    return Cpanel::AdvConfig::save_app_conf( $service, 0, \%save_conf );
}

my $_auth_policy_hash_nonce;

sub _auth_policy_hash_nonce {
    return ( $_auth_policy_hash_nonce ||= Cpanel::Rand::Get::getranddata( 8, [ 0 .. 9 ] ) );
}

sub process_config_changes {
    my ($conf_ref) = @_;

    $conf_ref->{'hulk_auth_passwd'}       ||= Cpanel::Hulk::Key::cached_fetch_key('dovecot');
    $conf_ref->{'auth_policy_hash_nonce'} ||= _auth_policy_hash_nonce();

    Cpanel::FileUtils::Write::overwrite(
        $Cpanel::Dovecot::PLAINTEXT_CONFIG_CACHE_FILE,
        $conf_ref->{'disable_plaintext_auth'} || $soft_defaults->{'disable_plaintext_auth'},
        0644,
    );

    if ( $conf_ref->{'auth_policy_hash_nonce'} && $conf_ref->{'hulk_auth_passwd'} ) {
        Cpanel::FileUtils::Write::overwrite(
            Cpanel::AdvConfig::dovecot::utils::find_dovecot_auth_policy_conf(),
            "auth_policy_hash_nonce = $conf_ref->{'auth_policy_hash_nonce'}\n" . "auth_policy_server_api_header = X-API-Key:dovecot:$conf_ref->{'hulk_auth_passwd'}\n",
            0640,
        );
    }

    Cpanel::FileUtils::Write::overwrite(
        $Cpanel::Dovecot::Constants::PROTOCOLS_FILE,
        $conf_ref->{'protocols'} || $soft_defaults->{'protocols'},
        0644
    );

    if ( $conf_ref->{'include_trash_in_quota'} ) {
        Cpanel::Dovecot::IncludeTrashInQuota->set_on();
    }
    else {
        Cpanel::Dovecot::IncludeTrashInQuota->set_off();
    }

    return 1;
}

sub check_syntax {
    my $dovecot_conf = shift;
    my $dovecot_bin  = Cpanel::AdvConfig::dovecot::utils::find_dovecot_bin();
    unless ( -e $dovecot_conf ) {
        return wantarray ? ( 0, $dovecot_conf . ' is missing!' ) : 0;
    }
    unless ( -x $dovecot_bin ) {
        return wantarray ? ( 0, $dovecot_bin . ' is missing or not executable!' ) : 0;
    }

    my $response = Cpanel::SafeRun::Errors::saferunallerrors( $dovecot_bin, '-c', $dovecot_conf, '-n' );
    my $valid    = $response !~ /^Fatal: Invalid configuration/s;

    # Test for auth & anvil client limit warnings
    my $values_to_change = {};
    if ( $response =~ m/service auth \{ client_limit=\d+ \} is lower than required under max. load \((\d+)\)/ ) {
        $values_to_change->{'auth_required_client_limit'} = $1;
    }
    if ( $response =~ m/service anvil \{ client_limit=\d+ \} is lower than required under max. load \((\d+)\)/ ) {
        $values_to_change->{'anvil_required_client_limit'} = $1;
    }
    return wantarray ? ( $valid, $response, $values_to_change ) : $valid;
}

# Returns ( $template_file_or_0, $undef_or_error ) as per Cpanel::Template::Files::get_service_template_file
sub get_template_file {
    Cpanel::Context::must_be_list();

    return Cpanel::Template::Files::get_service_template_file( $service, 0, 'main' );
}

#Might be better to call verify_that_config_file_is_valid() so that the
#caller can see what the error is?
sub check_if_config_file_is_valid {
    my ($file) = @_;
    Cpanel::Context::must_be_list();
    return _verify_that_config_file_is_valid($file);
}

# Currently we're only checking for one bit of text,
#but if we expand this.. please do something more efficient.
sub _verify_that_config_file_is_valid {
    my ($file) = @_;
    Cpanel::Context::must_be_list();

    my @errs = ();

    my %checks = (
        lmtp => {
            check => sub { !Cpanel::FileUtils::Lines::has_txt_in_file( $file, '\Aservice[ \t]*lmtp[ \t]*{' ) },
            error => 'Missing LMTP setup in configuration file! (service lmtp { ... })',
        },
        auth_policy => {
            check => sub { !Cpanel::FileUtils::Lines::has_txt_in_file( $file, '\Aauth_policy_server_url' ) },
            error => 'Missing auth_policy_server_url setup in configuration file! (auth_policy_server_url)',
        },
        dovecot_wrap => {
            check => sub { Cpanel::FileUtils::Lines::has_txt_in_file( $file, '\A\s*args\s*=\s*/usr/local/cpanel/bin/dovecot-wrap' ) },
            error => '/usr/local/cpanel/bin/dovecot-wrap is still present in configuration file!',
        },
        ssl_conf => {
            check => sub { !Cpanel::FileUtils::Lines::has_txt_in_file( $file, '\A\s*!include_try\s*/etc/dovecot/ssl.conf' ) },
            error => 'Missing the include for /etc/dovecot/ssl.conf! ( !include_try /etc/dovecot/ssl.conf )',
        },
        expire_plugin => {
            check => sub { Cpanel::FileUtils::Lines::has_txt_in_file( $file, '\A\s*mail_plugins\s*=.*\s+expire\s+' ) },
            error => 'Expire plugin is still present in configuration file!',
        },
    );

    for my $c ( keys %checks ) {
        if ( $checks{$c}{check}->() ) {
            push( @errs, "Configuration file $file is invalid: $checks{$c}{error}" );
        }
    }

    return 1 if !@errs;
    Cpanel::Debug::log_info($_) for @errs;
    return ( 0, @errs );

}

sub check_if_local_template_is_valid {
    Cpanel::Context::must_be_list();

    # if we don't have a local config the local config is a-ok as we'll use the default instead.
    my $template_file = has_local_template();
    return 1 if !$template_file;

    # Currently we're only checking for one bit of text, but if we expand this.. please do something more efficient
    return check_if_config_file_is_valid($template_file);
}

sub has_local_template {
    my ( $template_file, $error ) = get_template_file();
    return 0 unless $template_file;

    # if we don't have a local config the local config is a-ok as we'll use the default instead.
    return $template_file if $template_file =~ /\.local$/;
    return 0;
}

sub send_icontact {
    my ( $template_file, @errs ) = @_;

    return if !$template_file;

    require Cpanel::Notify;
    return Cpanel::Notify::notification_class(
        'class'            => 'Check::LocalConfTemplate',
        'application'      => 'Check::LocalConfTemplate',
        'status'           => 1,
        'constructor_args' => [
            'origin'   => 'dovecot_check_local_template',
            'service'  => 'dovecot',
            'template' => $template_file,
            'errors'   => \@errs,
        ]
    );
}

sub update_templates {
    my $versioned_service = shift || die "service not specified...can't determine location of templates";

    #TODO: safemkdir() actually does the recursive mkdir() for us;
    #it shouldn’t be necessary to write it out here manually.
    foreach my $dir ( $_TEMPLATES_TARGET_DIR, "$_TEMPLATES_TARGET_DIR/$versioned_service" ) {
        Cpanel::SafeDir::MK::safemkdir( $dir, '0755' ) unless ( -d $dir );
    }

    my $system_template = "$_TEMPLATES_SOURCE_DIR/dovecot/main.default";
    my $system_mtime    = ( stat($system_template) )[9];

    my $target_template = "$_TEMPLATES_TARGET_DIR/$versioned_service/main.default";

    if ( -e $target_template ) {
        my $target_mtime = ( stat($target_template) )[9];

        my $why_replace;
        my $short_why;

        if ( $target_mtime <= $system_mtime ) {
            $why_replace = "This system’s custom Dovecot configuration appears to be older than the cPanel-supplied configuration.";
            $short_why   = 'outdated';
        }
        elsif ( $target_mtime > time ) {
            $why_replace = sprintf( "This system’s custom Dovecot configuration has a last-modified time that is in the future (%s).", Cpanel::Time::ISO::unix2iso($target_mtime) );
            $short_why   = 'timewarp';
        }
        elsif ( !( _verify_that_config_file_is_valid($target_template) )[0] ) {
            $why_replace = "This system’s custom Dovecot configuration is invalid or outdated";
            $short_why   = 'invalid';
        }

        if ($why_replace) {
            my $rename_to = join '.', $target_template, $short_why, Cpanel::Time::ISO::unix2iso(), Cpanel::Rand::Get::getranddata( 8, [ 0 .. 9 ] );

            warn "$why_replace The system will rename the custom configuration to “$rename_to” and install a default configuration.\n";

            rename $target_template, $rename_to or do {
                warn "The system failed to rename “$target_template” to “$rename_to” because of an error: $!";

                #I guess just clobber here? Better that, probably,
                #than for Dovecot to stay broken.
            };
        }
        else {
            return 0;
        }
    }

    Cpanel::FileUtils::Copy::safecopy( $system_template, $target_template );
    chmod( oct(644), $target_template );

    Cpanel::ServerTasks::schedule_task( ['DovecotTasks'], 180, 'handle_imunify_dovecot_extension' );

    # Since the main.default template was updated, we should notify that main.local templates may need manual changes.
    my $local = has_local_template();
    send_icontact($local) if $local;

    return 1;
}

sub _setup_soft_defaults {
    $soft_defaults->{'plugin'}->{'quota_rule'} = 'INBOX.Trash:ignore';
    $soft_defaults->{'first_valid_uid'} = Cpanel::OS::default_sys_uid_min();
    return;
}

sub _allow_domainowner_mail_pass {
    return -e '/var/cpanel/allow_domainowner_mail_pass' ? 1 : 0;
}

sub _augment_hard_defaults_with_xaps_topic_if_available {
    my ($hard_defaults) = @_;
    if ( -e Cpanel::APNS::Mail::Config::CERT_FILE() ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::SSL::Objects::Certificate::File');

        local $@;
        my $c_parse = eval { Cpanel::SSL::Objects::Certificate::File->new( 'path' => Cpanel::APNS::Mail::Config::CERT_FILE() )->parsed() };
        if ($@) {
            warn "The system was unable to parse the APNS certificate file '" . Cpanel::APNS::Mail::Config::CERT_FILE() . "' due to an error: $@\n";
            return 0;
        }

        if ( my $xaps_topic = $c_parse->{'subject'}{'userId'} ) {
            $hard_defaults->{'xaps_topic'} = $xaps_topic;
            return 1;
        }
    }

    return 0;
}

# Tested directly
# ssl_protocols has been phased out, but this function has been retained as a transitional feature.
sub _initialize_ssl_min_protocol_from_ssl_protocols_if_needed {
    my ($conf) = @_;

    # If the system does not support it do nothing
    return if !Cpanel::Dovecot::Compat::has_ssl_min_protocol();

    # If its already set in the config do nothing
    return if $conf->{'ssl_min_protocol'};

    if ( !length $conf->{'ssl_protocols'} ) {
        $conf->{'ssl_min_protocol'} = Cpanel::SSL::Defaults::default_ssl_min_protocol();
        return;
    }

    my %unsupported_protocols = ( 'SSLv2' => 1 );
    my $min_protocol          = 'SSLv3';
    my %current_protocols     = map { $_ => 1 } ( length $conf->{ssl_protocols} ? split( /\s+/, $conf->{ssl_protocols} ) : () );

    my $seen_not = 0;
    for my $protocol ( @ssl_protocol_order, @ssl_protocol_order ) {    # We transverse twice in case the ! protocol is the last one
        if ( $current_protocols{"!$protocol"} ) {
            $seen_not = $protocol;
        }
        elsif ( $seen_not || $current_protocols{$protocol} ) {
            $conf->{'ssl_min_protocol'} = $unsupported_protocols{$protocol} ? $min_protocol : $protocol;
            return;
        }
    }

    $conf->{'ssl_min_protocol'} = Cpanel::SSL::Defaults::default_ssl_min_protocol();
    return;
}

sub check_for_imunify_template {
    my $imunify = Cpanel::AdvConfig::dovecot::Imunify->new();
    if ( $imunify->needs_update() ) {
        return $imunify->refresh_local_template();
    }
    return 0;
}

1;
