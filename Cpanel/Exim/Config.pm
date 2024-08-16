package Cpanel::Exim::Config;

# cpanel - Cpanel/Exim/Config.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use IO::Handle ();
use Try::Tiny;

use Cpanel::Timezones                    ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Chdir                        ();
use Cpanel::ChildErrorStringifier        ();
use Cpanel::Domain::TLS                  ();
use Cpanel::Exception                    ();
use Cpanel::Fcntl                        ();
use Cpanel::SafeFile                     ();
use Cpanel::Rand                         ();
use Cpanel::Cpu                          ();
use Cpanel::PwCache                      ();
use Cpanel::FileUtils::TouchFile         ();
use Cpanel::LoadFile                     ();
use Cpanel::ConfigFiles                  ();
use Cpanel::Exim                         ();
use Cpanel::Exim::Config::Def            ();
use Cpanel::Exim::Config::Logselector    ();
use Cpanel::Exim::Config::Ports          ();
use Cpanel::Exim::Config::Check          ();
use Cpanel::FileUtils::Access            ();
use Cpanel::Logger                       ();
use Cpanel::FileUtils::Write             ();
use Cpanel::Rand::Get                    ();
use Cpanel::Chkservd                     ();
use Cpanel::Dir::Loader                  ();
use Cpanel::SafeRun::Errors              ();
use Cpanel::SafeDir::MK                  ();
use Cpanel::StringFunc::Replace          ();
use Cpanel::StringFunc::Trim             ();
use Whostmgr::Mail::RBL                  ();
use Cpanel::GreyList::Config             ();
use Cpanel::SSL::Defaults                ();
use Cpanel::NAT::Build                   ();
use Cpanel::Services::Enabled            ();
use Whostmgr::TweakSettings::Mail        ();

our $acls_dir            = '/usr/local/cpanel/etc/exim/acls';
our $SRS_SECRET_FILE     = '/var/cpanel/srs_secret';
our $HIDDEN_CONFIG_DIR   = '/var/cpanel/exim_hidden';
our $SRS_CONFIG_FILE     = '/var/cpanel/exim_hidden/srs_config';
our $SMARTHOST_AUTH_FILE = '/var/cpanel/exim_hidden/smarthost_auth';
our $SPAMD_OPTS          = 'retry=30s tmo=3m';                         # It really is named tmo and not timeout

### README WHEN CHANGING THE EXIM.CONF VERSION NUMBERS ####
# This version number system is supposed to express a range of compatible exim configurations when
# new functionality is added to the exim binary or the cPanel & WHM configuration. The range support
# is seldom used but you need to be aware of it when changing the version numbers.
#
# How it works:
# 1) The minimum exim.conf version is placed in etc/required_exim_acl_version
# 2) The maximum exim.conf version is placed in etc/exim/defacls/universal.dist
# 3) This module's $VERSION should be identical to the universal.dist version
# 4) Version numbers are compared with floating point math (10.9 is greater than 10.10)
# 5) cPanel & WHM major versions do not distinguish the exim.conf versions in any way
#
# To avoid colliding version numbers across cPanel & WHM releases:
# - If you are in a cPanel version 80 or higher
#   - Set the version to the cPanel version if it is not already this number or higher.
#   - Increment the version by 0.001 otherwise
# - If you are in a cPanel version before 80
#   - Increment by 0.0001 until it reaches 10.XXX9
#   - At 10.XXX9 increment by 0.0002
our $VERSION = 116.001;

our $FILTER_SOURCE_DIR  = '/usr/local/cpanel/etc/exim/sysfilter';
our $FILTER_TARGET_FILE = '/etc/cpanel_exim_system_filter';

# The values that replace %CPANEL-...% sections in the Exim config template
# files. Each value may itself include %CPANEL-...% references. If you
# augment this hash, be sure that you don’t create a reference cycle!
#
my %CPANEL_SUBSTITUTION = (
    'user-domain' => <<~'HERE',
        ${extract{6} \
            {:} \
            {${lookup \
                passwd{ \
                    ${lookup \
                        {$domain_data} \
                        lsearch{/etc/userdomains} \
                    } \
                } \
            }} \
        }
        HERE

    'domain-owner' => <<~'HERE',
        ${lookup \
            {$domain_data} \
            lsearch{/etc/userdomains} \
            {$value}}
        HERE

    'domain-owner-homedir' => <<~'HERE',
        ${extract \
            {5} \
            {::} \
            {${lookup \
                passwd{%CPANEL-domain-owner%} \
                {$value} \
            }} \
        }
        HERE

    'local-user-homedir' => <<~'HERE',
        ${extract \
            {5} \
            {::} \
            {${lookup \
                passwd{$local_part_data} \
                {$value} \
            }} \
        }
        HERE

    'domain-checked-untainted' => <<~'HERE',
        ${lookup \
            {$domain} \
            lsearch{/etc/userdomains} \
            {${perl{untaint} \
                {$domain} \
            }} \
        }
        HERE

    'helo-data' => <<~'HERE',
        ${if > \
            {${extract{size}{${stat:/etc/mailhelo}}}} \
            {0} \
            {${lookup \
                {${lc:${perl{get_message_sender_domain}}}} \
                lsearch{/etc/mailhelo} \
                {$value} \
                {${lookup \
                    {${if match_domain \
                        {$original_domain} \
                        {+relay_domains} \
                        {${lc:$original_domain}} \
                        {} \
                    }} \
                    lsearch{/etc/mailhelo} \
                    {$value} \
                    {${lookup \
                        {${perl{get_sender_from_uid}}} \
                        lsearch*{/etc/mailhelo} \
                        {$value} \
                        {$primary_hostname} \
                    }} \
                }} \
            }} \
            {$primary_hostname} \
        }
        HERE

    'smtp-interface' => <<~'HERE',
        ${if > \
            {${extract \
                {size} \
                {${stat:/etc/mailips}} \
            }} \
            {0} \
            {${lookup \
                {${lc:${perl{get_message_sender_domain}}}} \
                lsearch{/etc/mailips} \
                {$value} \
                {${lookup \
                    {${if match_domain \
                        {$original_domain} \
                        {+relay_domains} \
                        {${lc:$original_domain}} \
                        {} \
                    }} \
                    lsearch{/etc/mailips} \
                    {$value} \
                    {${lookup \
                        {${perl{get_sender_from_uid}}} \
                        lsearch*{/etc/mailips} \
                        {$value} \
                        {} \
                    }} \
                }} \
            }} \
        }
        HERE

    'yyyy-mm-dd' => <<~'HERE',
        ${substr \
            {0} \
            {4} \
            {$tod_zulu} \
        }-${substr \
            {4} \
            {2} \
            {$tod_zulu} \
        }-${substr \
            {6} \
            {2} \
            {$tod_zulu} \
        }
        HERE

    'sender-sysuser' => <<~'HERE',
        ${extract \
            {sender_sysuser} \
            {$address_data} \
        }
        HERE

    'trustedmailhosts-size' => <<~'HERE',
        ${extract \
            {size} \
            {${stat:/etc/trustedmailhosts}} \
        }
        HERE

    'address-redirect' => <<~'HERE',
        ${extract \
            {redirect} \
            {$address_data} \
        }
        HERE

    'local-username' => <<~'HERE',
        ${extract \
            {6} \
            {:} \
            {${lookup \
                passwd{$local_part_data} \
            }} \
        } \
        HERE
);

chomp %CPANEL_SUBSTITUTION;

#1) Sanity check $tls_in_sni; if not, use service default.
#2) If we have an exact-matching Domain TLS entry, use it.
#3) If we have a wildcard-matching Domain TLS entry, use it.
#4) Use service default.
#
#This string is tested directly.
sub _tls_template() {
    my $tls_template = <<'END';
${if and \
    { \
        {gt{$tls_in_sni}{}} \
        {!match{$tls_in_sni}{/}} \
    } \
    {${if exists {BASE_PATH/$tls_in_sni/combined} \
        {BASE_PATH/$tls_in_sni/combined} \
        {${if exists {${sg{BASE_PATH/$tls_in_sni/combined}{(.+/)[^.]+(.+/combined)}{\$1*\$2}}} \
            {${sg{BASE_PATH/$tls_in_sni/combined}{(.+/)[^.]+(.+/combined)}{\$1*\$2}}} \
            {/etc/DEFAULT} \
        }} \
    }} \
    {/etc/DEFAULT} \
}
END

    #Do substitutions on the template because if we do string interpolation
    #then we have to back-escape all of the “$” characters, which makes an
    #ugly template that much worse.
    my $base_path = Cpanel::Domain::TLS->BASE_PATH();
    $tls_template =~ s<BASE_PATH><$base_path>g;

    return $tls_template;
}

sub new ( $class, %OPTS ) {

    my $self = {%OPTS};

    if ( !exists $OPTS{'eximbin'} ) {
        ( $self->{'eximbin'}, $self->{'eximversion'}, $self->{'exim_caps'} ) = Cpanel::Exim::fetch_caps();
    }
    if ( !exists $OPTS{'localopts.shadow'} ) {
        $self->{'localopts.shadow'} = '/etc/exim.conf.localopts.shadow';
    }

    $self->{'rawout'} = '';
    bless $self, $class;

    return $self;
}

sub generate_config_file ($self) {    ## no critic(ProhibitExcessComplexity)

    $self->{'rawout'} = '';

    $self->ensure_setup() if !$self->{'no_ensure_setup'};

    if ( !-e '/etc/exim.conf.dist' && !-e '/usr/local/cpanel/etc/exim/distconfig/exim.conf.dist' ) {
        $self->{'rawout'} .= "$0: fatal: /etc/exim.conf.dist and /usr/local/cpanel/etc/exim/distconfig/exim.conf.dist' are missing\n";
        return ( 'status' => 0, 'rawout' => $self->{'rawout'} );
    }

    my @KILLCF;
    my %CF;

    my $message_linelength_limit_default = Whostmgr::TweakSettings::Mail->get_message_linelength_limit_default();

    my %SETTINGS = (
        'senderverify'                                 => 1,
        'rbl_whitelist_neighbor_netblocks'             => 1,
        'rbl_whitelist_greylist_common_mail_providers' => 1,
        'rbl_whitelist_greylist_trusted_netblocks'     => 0,
        'allowweakciphers'                             => 0,
        'smarthost_routelist'                          => '',
        'smarthost_username'                           => '',
        'smarthost_password'                           => '',
        'callouts'                                     => 0,
        'exiscanall'                                   => 0,
        'max_spam_scan_size'                           => 1000,
        'setsenderheader'                              => 0,
        'spam_deferok'                                 => 1,
        'malware_deferok'                              => 1,
        'message_linelength_limit'                     => $message_linelength_limit_default,
        'hosts_avoid_pipelining'                       => 0,
        'mailbox_quota_query_timeout'                  => '45s',
    );

    # Exim configuration uses a combination of configuration files and filesystem layout
    # to dictate it's configuration. The "Cpanel::Dir::Loader::load_multi_level_dir" loads the filesystem
    # information, then everything else comes from several configuration files.
    # CAVEAT: in some instances an item is configured through both the configuration files
    #         and through the filesystem. i.e. RBLs need to be active in config file and
    #         RBL template must exist.

    $self->create_custom_acl_files() || return ( 'status' => 0, 'rawout' => $self->{'rawout'} );

    my %ACLS;
    my %ACLBLOCKS = Cpanel::Dir::Loader::load_multi_level_dir($acls_dir);
    foreach my $aclblock ( sort keys %ACLBLOCKS ) {
        if ( $self->{'acl_dry_run'} ) {
            my %POSSIBLE_FILES = map { $_ => undef } @{ $ACLBLOCKS{$aclblock} };
            foreach my $file ( grep( /\.dry_run$/, @{ $ACLBLOCKS{$aclblock} } ) ) {
                my $non_dry_run_file = $file;
                $non_dry_run_file =~ s/\.dry_run$//;
                delete $POSSIBLE_FILES{$non_dry_run_file};
            }
            $ACLBLOCKS{$aclblock} = [ keys %POSSIBLE_FILES ];

        }
        else {
            $ACLBLOCKS{$aclblock} = [ grep( !/\.dry_run$/, @{ $ACLBLOCKS{$aclblock} } ) ];
        }
        foreach my $acl ( @{ $ACLBLOCKS{$aclblock} } ) {    #rbls must be explictly enabled
            $ACLS{$acl} = ( $acl =~ /_rbl$/ ? 0 : 1 );
            if ( $acl eq 'greylisting' ) {
                $ACLS{$acl} = Cpanel::GreyList::Config::is_enabled();
            }
        }
    }

    _merge_array_into_hash_with_fixed_value( \@Cpanel::Exim::Config::Def::OFF_DEFAULT_ACLS, \%ACLS, 0 );

    if ( $self->{'exim_caps'}{'no_forward_outbound_spam_over_int'} ) {
        $ACLS{'no_forward_outbound_spam_over_int'} = 1;
    }
    elsif ( $self->{'exim_caps'}{'no_forward_outbound_spam'} ) {
        $ACLS{'no_forward_outbound_spam'} = 1;
    }

    my %FILTERS = Cpanel::Dir::Loader::load_dir_as_hash_with_value( '/usr/local/cpanel/etc/exim/sysfilter/options', 1 );
    _merge_array_into_hash_with_fixed_value( \@Cpanel::Exim::Config::Def::OFF_DEFAULT_FILTERS, \%FILTERS, 0 );

    my $config_template = Cpanel::Exim::fetch_config_template_name();

    $self->load_settings_acls_filters_from_local_conf( \%SETTINGS, \%ACLS, \%FILTERS );
    $self->load_settings_acls_filters_from_local_conf( \%SETTINGS, \%ACLS, \%FILTERS, 'localopts.shadow' );

    if ( !$self->{'exim_caps'}->{'notquit'} ) {
        $ACLS{'ratelimit'} = 0;
    }

    # Create RBL templates
    my $rbl_href = Whostmgr::Mail::RBL::list_rbls_from_yaml();
  RBL_TEMPLATE_LOOP:
    while ( my ( $name, $data ) = each %{$rbl_href} ) {
        if ( $ACLS{"${name}_rbl"} ) {
            Whostmgr::Mail::RBL::write_rbl_template( $name, @{ $data->{'dnslists'} } ) or do {
                $self->warn("Failed to write RBL template for $name: $!");
                next RBL_TEMPLATE_LOOP;
            };
            if ( !grep { $_ eq "${name}_rbl" } @{ $ACLBLOCKS{'ACL_RBL_BLOCK'} } ) {

                # Re-set filesytem dependent configutation
                my @rbls = @{ $ACLBLOCKS{'ACL_RBL_BLOCK'} };
                push @rbls, "${name}_rbl";
                @{ $ACLBLOCKS{'ACL_RBL_BLOCK'} } = sort @rbls;    # RBLs have to be sorted
            }
        }
    }

    # tweaksettings should already have checked for this and rejected nonexistent values
    if ( defined $SETTINGS{'systemfilter'} ) {

        # value will be set to disabled value really means to disable it
        #   vs undef which will use the default value ( case 54413 )
        if ( $SETTINGS{'systemfilter'} eq 'disabled' ) {
            delete $SETTINGS{'systemfilter'};
        }
        elsif ( $SETTINGS{'systemfilter'} ne q{}
            && !-e $SETTINGS{'systemfilter'} ) {
            $SETTINGS{'systemfilter'} = '/etc/cpanel_exim_system_filter';
        }
    }
    else {

        # should be on by default during install; case 54413
        $SETTINGS{'systemfilter'} = '/etc/cpanel_exim_system_filter';
    }

    if ( exists $SETTINGS{'systemfilter'} && defined $SETTINGS{'systemfilter'} && $SETTINGS{'systemfilter'} eq '/etc/cpanel_exim_system_filter' ) {
        $self->generate_cpanel_system_filter( \%FILTERS );
    }

    $self->load_local_exim_config( \%CF, \@KILLCF );

    $CF{'CONFIG'} ||= '';
    if ( $CF{'CONFIG'} !~ /\n\n$/ ) {
        $CF{'CONFIG'} .= "\n";
    }

    my @REPLACELIST;
    my %REPLACETEXT;

    $CF{'ACLBLOCK'} ||= Cpanel::LoadFile::loadfile('/usr/local/cpanel/etc/exim/defacls/universal.dist');
    $SETTINGS{'dont_delay_greylisting_trusted_hosts'}         = delete $ACLS{'dont_delay_greylisting_trusted_hosts'}         // 1;
    $SETTINGS{'dont_delay_greylisting_common_mail_providers'} = delete $ACLS{'dont_delay_greylisting_common_mail_providers'} // 0;

    $self->insert_acl_blocks_into_cf( \%CF, \%ACLBLOCKS, \%ACLS, \%SETTINGS );

    if ( $CF{'ACLBLOCK'} !~ m/^\s*acl_smtp_connect:/m ) {
        $self->{'rawout'} .= "Disabling the ratelimit & spammerlist acl because the custom acl block prevented us from installing the acl_smtp_connect acls.\n";
        $ACLS{'spammerlist'} = 0;    #if the acls are not in the block we cannot add them
        $ACLS{'ratelimit'}   = 0;    #if the acls are not in the block we cannot add them
    }

    if ( $ACLS{'ratelimit'} && $CF{'ACLBLOCK'} !~ m/^\s*acl_smtp_notquit:/m ) {
        $self->{'rawout'} .= "Disabling the ratelimit acl because the custom acl block prevented us from installing the acl_smtp_notquit acls.\n";
        $ACLS{'ratelimit'} = 0;      #if the acls are not in the block we cannot add them
    }

    my %ACL_OPTS;
    $ACL_OPTS{'ACL_MAX_SPAM_SCAN_SIZE'} = int $SETTINGS{'max_spam_scan_size'} || 1000;
    $ACL_OPTS{'ACL_SPAM_HEADER'}        = $SETTINGS{'spam_header'}            || '';
    $ACL_OPTS{'ACL_RBL_WHITELIST'}      = '';
    my $eximscanuser = _get_eximscanner_user();
    $ACL_OPTS{'ACL_EXIMSCANUSER'} = $eximscanuser;

    if ( $SETTINGS{'rbl_whitelist'} ) {
        my @hostlist = split( /[;,\s]+/, $SETTINGS{'rbl_whitelist'} );
        if (@hostlist) {
            $ACL_OPTS{'ACL_RBL_WHITELIST'} = '!hosts = <, ' . join( ' , ', @hostlist );
        }
    }
    $ACL_OPTS{'ACL_RBL_WHITELIST'} .= "\n\t\t!domains = +skip_rbl_domains" if -e '/etc/skiprbldomains';

    if ( $SETTINGS{'rbl_whitelist_neighbor_netblocks'} ) {
        $ACL_OPTS{'ACL_RBL_WHITELIST'} .= "\n\t\t!hosts = +neighbor_netblocks" if -e '/etc/neighbor_netblocks';
    }
    if ( $SETTINGS{'rbl_whitelist_greylist_common_mail_providers'} ) {
        $ACL_OPTS{'ACL_RBL_WHITELIST'} .= "\n\t\t!hosts = +greylist_common_mail_providers" if -e '/etc/greylist_common_mail_providers';
    }
    if ( $SETTINGS{'rbl_whitelist_greylist_trusted_netblocks'} ) {
        $ACL_OPTS{'ACL_RBL_WHITELIST'} .= "\n\t\t!hosts = +greylist_trusted_netblocks" if -e '/etc/greylist_trusted_netblocks';
    }

    foreach my $aclblock ( keys %ACL_OPTS ) {
        $CF{'ACLBLOCK'} =~ s/\[\s*\%\s*\Q$aclblock\E\s*\%\s*\]/$ACL_OPTS{$aclblock}/gm;
    }

    $CF{'ACLBLOCK'} =~ s/^\s*\[\s*\%\s*[^\%]+\s*\%\s*\]//gm;    #remove any missing ones

    my $acl_spam_handler = 0;
    if ( $CF{'ACLBLOCK'} =~ m/^\s*spam\s*=/m ) {
        $acl_spam_handler = 1;
        $self->{'rawout'} .= "The system detected spam handling in acls and will now disable Apache SpamAssassin™ in routers and transports!\n" if $self->{'debug'};
        my @DISABLE = ( "virtual_sa_user", "sa_localuser", "virtual_sa_userdelivery", "local_sa_delivery" );
        foreach my $sec (@DISABLE) {
            $REPLACETEXT{$sec} = "\n        \n";
        }
        push @REPLACELIST, @DISABLE;
    }

    if ( !$SETTINGS{'malware_deferok'} ) {
        $self->{'rawout'} .= "malware/defer_ok is disabled\n" if $self->{'debug'};
        foreach my $cf ( keys %CF ) {
            if ( $cf =~ m/ACL/ ) {
                $CF{$cf} =~ s/^([\s\t]*malware[\s\t]*=[\s\t]*[^\/]+)\/defer_ok/$1/gm;
            }
        }
    }

    if ( !$SETTINGS{'spam_deferok'} ) {
        $self->{'rawout'} .= "spam/defer_ok is disabled\n" if $self->{'debug'};
        foreach my $cf ( keys %CF ) {
            if ( $cf =~ m/ACL/ ) {
                $CF{$cf} =~ s/^([\s\t]*spam[\s\t]*=[\s\t]*[^\/]+)\/defer_ok/$1/gm;
            }
        }
    }

    if ( !$SETTINGS{'senderverify'} ) {
        foreach my $cf ( keys %CF ) {
            if ( $cf =~ m/ACL/ ) {

                # case CPANEL-1569: The new SMTP delay feature will not honor the exemptions if Sender Verification is disabled.
                # keep lines that also reference recent_authed_mail_ips as they are likely exemptions to smtp delays
                $CF{$cf} = join( "\n", grep { m{\+recent_authed_mail_ips} || !/(verify\s*=\s*sender|senderverifybypass)/ } split( /\n/, $CF{$cf} ) );
            }
        }
    }

    if ( !$self->{'exim_caps'}->{'add_header'} ) {
        foreach my $cf ( keys %CF ) {
            if ( $cf =~ m/ACL/ && $CF{$cf} =~ m/^\s*add_header/m ) {
                $CF{$cf} =~ s/^(\s*)add_header/$1message/mg;
            }
        }
    }

    if ( !$SETTINGS{'callouts'} ) {
        foreach my $cf ( keys %CF ) {
            if ( $cf =~ m/ACL/ && $CF{$cf} =~ m/verify[\s\t]*=[\s\t]*/m ) {
                $CF{$cf} =~ s/sender\/callout=?\d*s?/sender/g;
            }
        }
    }

    if ( $SETTINGS{'smarthost_routelist'} ) {
        $SETTINGS{'smarthost_routelist'} =~ s/^\s+//;
        $SETTINGS{'smarthost_routelist'} =~ s/\s+$//;
        $SETTINGS{'smarthost_routelist'} =~ s/\n+$//;

        if ( $SETTINGS{'smarthost_auth_required'} ) {
            for my $smkey (qw(smarthost_username smarthost_password)) {
                $SETTINGS{$smkey} = _perform_client_send_escapes( $SETTINGS{$smkey} );
            }
        }
    }

    if ( exists $CF{'CONFIG'} ) {
        my $cf_new = '';
        foreach my $cfopt ( split( /\n/, $CF{'CONFIG'} ) ) {
            if ( $cfopt =~ m/\S+/ ) {    #does not need to have a = .. ie may be perl_at_start
                my $optname = ( split( /=/, $cfopt ) )[0];
                $optname =~ s/^\s+|\s+$//g;
                my $map = {
                    'daemon_smtp_ports'    => \%Cpanel::Exim::Config::Ports::LISTEN_PORTS,
                    'daemon_smtp_port'     => \%Cpanel::Exim::Config::Ports::LISTEN_PORTS,
                    'tls_on_connect_ports' => \%Cpanel::Exim::Config::Ports::TLS_ON_CONNECT_PORTS,
                };
                if ( $map->{$optname} ) {
                    my $value = ( split( /=/, $cfopt ) )[1];
                    $value =~ s/\s//g;

                    # If we see one of these config settings, we should
                    # completely override the defaults with it.
                    %{ $map->{$optname} } = map { $_ => 1 } grep { /^\d+$/ && $_ < 65535 } split /[,:]/, $value;
                }
                else {
                    $cf_new .= $cfopt . "\n";
                    push( @KILLCF, $optname );
                }
            }
        }
        $CF{'CONFIG'} = $cf_new;
    }
    $self->{'rawout'} .= "Configured options list is: " . join( '|', @KILLCF ) . "\n" if $self->{'debug'};

    my @PROVIDEDOPTS;
    my @CONFIG_OPTS =
      map { ( !m/^#/ && !m/^\s*$/ ) ? ( m/=/ ? $_ : "$_ = true" ) : () } split( /\n/, Cpanel::LoadFile::loadfile('/usr/local/cpanel/etc/exim/config_options') );

    push @CONFIG_OPTS, "domainlist skip_rbl_domains = lsearch;/etc/skiprbldomains" if -e '/etc/skiprbldomains';
    my $exim_alt_port = Cpanel::Chkservd::geteximport(1);    #first arg allows fetch more than the first port

    if ( $SETTINGS{'smarthost_routelist'} && $SETTINGS{'smarthost_auth_required'} ) {

        # Outside of route_list, the semicolon separator needs to be explicit if another isn't given.
        # Also keep track of the separator character separately:
        my $list_prefix = $SETTINGS{'smarthost_routelist'} =~ m/^\s*<(\S)/ ? '' : '<; ';
        my $separator   = $list_prefix eq ''                               ? $1 : ';';

        my $smarthost_hostlist = 'hostlist smarthosts = <' . $separator . ' ${tr{${map{' . $list_prefix . $SETTINGS{'smarthost_routelist'} . '}{${reduce{${perl{extract_hosts_from_route_list_item}{$item}}}{}{${if def:value {$value\n}{}}${perl{convert_to_hostlist_item}{$item}{\n}}}}}}}{\n}{' . $separator . '}}';

        push @CONFIG_OPTS, $smarthost_hostlist;
    }

    # If this is set and it's the default ("25"), we ignore this value, as it
    # may have been overridden by daemon_smtp_ports above.
    if ( $exim_alt_port && $exim_alt_port ne '25' ) {
        foreach my $port ( split( m/\s*\,\s*/, $exim_alt_port ) ) {
            $Cpanel::Exim::Config::Ports::LISTEN_PORTS{$port} = 1 if ( $port =~ /^[0-9]+$/ && $port < 65535 && $port > 0 );
        }
    }

    $self->_setup_srs_config_file();

    Cpanel::NAT::Build::update();

    require Cpanel::Exim::Config::NAT;
    if ( my $nat_cfg = Cpanel::Exim::Config::NAT::config_file_section() ) {
        push @KILLCF, Cpanel::Exim::Config::NAT::KILLCF();
        $CF{'CONFIG'} .= $nat_cfg;
    }

    # add or remove the include for the srs_config file
    push @KILLCF, 'hide srs_config', 'srs_config';
    if ( $SETTINGS{'srs'} && $CF{'CONFIG'} !~ m/^\s*\.include_if_exists $SRS_CONFIG_FILE/m ) {
        $CF{'CONFIG'} .= ".include_if_exists $SRS_CONFIG_FILE\n";
    }
    elsif ( !$SETTINGS{'srs'} ) {
        $CF{'CONFIG'} =~ s/^\s*\.include_if_exists $SRS_CONFIG_FILE.*//gm;
    }

    my $cpucount = Cpanel::Cpu::getcpucount();
    push @PROVIDEDOPTS, 'deliver_queue_load_max';
    push @CONFIG_OPTS,  'deliver_queue_load_max = ' . ( $cpucount * 3 );
    push @PROVIDEDOPTS, 'queue_only_load';
    push @CONFIG_OPTS,  'queue_only_load = ' . ( $cpucount * 6 );
    push @PROVIDEDOPTS, 'daemon_smtp_ports';
    push @CONFIG_OPTS,  'daemon_smtp_ports = ' . join( ' : ', sort keys %Cpanel::Exim::Config::Ports::LISTEN_PORTS );
    push @PROVIDEDOPTS, 'tls_on_connect_ports';
    push @CONFIG_OPTS,  'tls_on_connect_ports = ' . join( ' : ', sort keys %Cpanel::Exim::Config::Ports::TLS_ON_CONNECT_PORTS );

    if ( Cpanel::PwCache::getpwnam('cpaneleximfilter') ) {
        push @CONFIG_OPTS,  'system_filter_user = cpaneleximfilter';
        push @CONFIG_OPTS,  'system_filter_group = cpaneleximfilter';
        push @PROVIDEDOPTS, 'system_filter_user', 'system_filter_group';
    }

    my $smtputf8 = $SETTINGS{'smtputf8_advertise_hosts'} // ':';
    push @PROVIDEDOPTS, 'smtputf8_advertise_hosts';
    push @CONFIG_OPTS,  "smtputf8_advertise_hosts = $smtputf8";

    my $default_protos = lc Cpanel::SSL::Defaults::default_protocol_list( { type => 'negative', delimiter => ' ', negation => '+no_', all => '', separator => '_' } );
    my $protos         = $SETTINGS{'openssl_options'} // $default_protos;
    push @PROVIDEDOPTS, 'openssl_options';
    push @CONFIG_OPTS,  "openssl_options = $protos";

    if ( !$SETTINGS{'allowweakciphers'} ) {
        my $ciphers = $SETTINGS{'tls_require_ciphers'} // Cpanel::SSL::Defaults::default_cipher_list();
        push @PROVIDEDOPTS, 'tls_require_ciphers';
        push @CONFIG_OPTS,  "tls_require_ciphers = $ciphers";
    }
    else {
        $self->{'rawout'} .= "allowweakciphers is set. allowing all tls ciphers.\n" if $self->{'debug'};
    }

    if ( $SETTINGS{'dsn_advertise_hosts'} ) {
        push @PROVIDEDOPTS, 'dsn_advertise_hosts';
        push @CONFIG_OPTS,  "dsn_advertise_hosts = $SETTINGS{'dsn_advertise_hosts'}";
    }

    my ( $acl_content_ref, $has_acl_content_ref ) = $self->check_acls_for_content( \%CF );

    foreach my $acl_config ( map { ( split( /\s*=\s*/, $_ ) )[0] } grep( /^acl_/, @CONFIG_OPTS ) ) {
        if ( !$has_acl_content_ref->{$acl_config} ) {
            @CONFIG_OPTS = grep( !/^\Q$acl_config\E\s*=/, @CONFIG_OPTS );
        }
        else {
            $self->{'rawout'} .= "ACL: $acl_config is active\n" if $self->{'debug'};
        }
    }
    if ( !$self->{'exim_caps'}->{'content_scanning'} ) {
        @CONFIG_OPTS = grep( !/^\s*(?:acl_smtp_mime|acl_not_smtp_mime)\s*=/, @CONFIG_OPTS );
        $self->{'rawout'} .= "ACL: acl_smtp_mime and acl_not_smtp_mime is disabled because exim is missing content_scanning support\n" if $self->{'debug'};
    }

    if ( $has_acl_content_ref->{'acl_smtp_connect'} ) {
        if ( $acl_content_ref->{'acl_smtp_connect'} !~ m/accept[\n\s\r]*$/ ) {
            $self->{'rawout'} .= "ACL: acl_smtp_connect not installed because it does not have an accept at the end.\n" if $self->{'debug'};
            @CONFIG_OPTS = grep( !/^\s*acl_smtp_connect\s*=/, @CONFIG_OPTS );
        }
    }
    foreach my $optional_directive (qw(keep_environment add_environment)) {
        if ( !$self->{'exim_caps'}{'directives'}{$optional_directive} ) {
            $CF{'CONFIG'} =~ s/^\s*$optional_directive\s*=.*//gm;
            @CONFIG_OPTS = grep( !/^\s*$optional_directive\s*=/, @CONFIG_OPTS );
            $self->{'rawout'} .= "$optional_directive is disabled because exim is missing support\n" if $self->{'debug'};
        }
    }
    while ( my $cfopt = shift(@CONFIG_OPTS) ) {
        if ( $cfopt !~ m/^\s*$/ ) {
            my $optname = ( split( /=/, $cfopt ) )[0];
            $optname =~ s/^\s+|\s+$//g;
            if ( !grep( /^\Q$optname\E$/, @KILLCF ) ) {
                $CF{'CONFIG'} .= "\n$cfopt\n";
                push( @PROVIDEDOPTS, $optname );
                push( @KILLCF,       $optname );
            }
        }
    }

    if ( $self->{'exim_caps'}->{'exiscan'} && $CF{'CONFIG'} !~ m/^av_scanner\s*=/m ) {
        push @PROVIDEDOPTS, "av_scanner";
        push @KILLCF,       "av_scanner";
        $CF{'CONFIG'} .= "\nav_scanner = clamd:/var/clamd\n";
    }

    if ( $CF{'CONFIG'} !~ /^[ \t]*timezone[ \t]*=/m ) {
        push @PROVIDEDOPTS, "timezone";
        push @KILLCF,       "timezone";
        $CF{'CONFIG'} .= "\ntimezone = " . Cpanel::Timezones::calculate_TZ_env() . "\n";
    }

    if ( Cpanel::Services::Enabled::is_provided("spamd") && $CF{'CONFIG'} !~ /^spamd_address\s*=/m ) {
        push @PROVIDEDOPTS, "spamd_address";
        push @KILLCF,       "spamd_address";
        if ( -e "/var/run/spamd.sock" ) {
            $CF{'CONFIG'} .= "\nspamd_address = /var/run/spamd.sock $SPAMD_OPTS\n";
        }
        else {
            $CF{'CONFIG'} .= "\nspamd_address = 127.0.0.1 783 $SPAMD_OPTS\n";
        }
    }

    $self->{'rawout'} .= "Provided options list is: " . join( '|', @PROVIDEDOPTS ) . "\n" if $self->{'debug'};

    push( @KILLCF, 'tls_certificate' );
    push( @KILLCF, 'tls_privatekey' );
    push( @KILLCF, 'tls_verify_certificates' );

    my ($default_base);

    if ( _use_myexim_cert() ) {
        $default_base = 'myexim';

        $self->{'rawout'} .= "Using user installed ssl certificate in key (/etc/myexim.key & /etc/myexim.crt)\n" if $self->{'debug'};
    }
    else {
        $default_base = 'exim';
    }

    #Exim will happily read the key from the certificate file.
    if ( $CF{'CONFIG'} !~ /^\s*tls_certificate\s*=/m ) {
        my $crt_dir = _tls_template() =~ s<DEFAULT><$default_base.crt>rg;
        $CF{'CONFIG'} .= "\ntls_certificate = $crt_dir\n";
    }

    #This is here only because the default service certs aren’t saved
    #with the key and CAB in the same file.
    if ( $CF{'CONFIG'} !~ /^\s*tls_privatekey\s*=/m ) {
        my $key_dir = _tls_template() =~ s<DEFAULT><$default_base.key>rg;
        $CF{'CONFIG'} .= "\ntls_privatekey = $key_dir\n";
    }

    push( @KILLCF, 'system_filter' );
    push( @KILLCF, 'log_selector' );

    Cpanel::Exim::Config::Logselector::set_log_selector_option( \%CF );

    # match was previously broken would not match "system_filter = X, only system_filter=X"
    if ( $CF{'CONFIG'} =~ m/^\s*system_filter\s*=/m ) {
        if ( defined $SETTINGS{'systemfilter'} && $SETTINGS{'systemfilter'} ne q{} ) {
            $CF{'CONFIG'} =~ s/^\s*system_filter\s*=.*/system_filter = $SETTINGS{'systemfilter'}/gm;
        }
        else {
            $CF{'CONFIG'} =~ s/^\s*system_filter\s*=.*//gm;
        }
    }
    else {
        if ( defined $SETTINGS{'systemfilter'} && $SETTINGS{'systemfilter'} ne q{} ) {
            $CF{'CONFIG'} .= "\nsystem_filter = $SETTINGS{'systemfilter'}\n\n";
        }
    }

    if ( $SETTINGS{'setsenderheader'} ) {
        push( @KILLCF, 'local_from_check' );
        if ( $CF{'CONFIG'} =~ m/^[\s\t]*local_from_check.*/m ) {
            if ( defined $SETTINGS{'systemfilter'} && $SETTINGS{'systemfilter'} ne q{} ) {
                $CF{'CONFIG'} =~ s/^[\s\t]*local_from_check.*/local_from_check = true/gm;
            }
            else {
                $CF{'CONFIG'} =~ s/^[\s\t]*local_from_check.*//gm;
            }
        }
        else {
            if ( defined $SETTINGS{'systemfilter'} && $SETTINGS{'systemfilter'} ne q{} ) {
                $CF{'CONFIG'} .= "\nlocal_from_check = true\n";
            }
        }
    }

    my %INSERTTEXT;
    $self->load_dir_contents_into_hash( '/usr/local/cpanel/etc/exim/cf', [], \%INSERTTEXT );
    $self->_fill_template_values( \%INSERTTEXT, \%SETTINGS );

    my $insertregex = join( '|', keys %INSERTTEXT );
    $self->{'rawout'} .= "Exim Insert Regex is: ${insertregex}\n" if $self->{'debug'};

    $self->load_dir_contents_into_hash( '/usr/local/cpanel/etc/exim/replacecf', \@REPLACELIST, \%REPLACETEXT );
    $self->_fill_template_values( \%REPLACETEXT, \%SETTINGS );

    # Switch authenticators to secure versions when secure auth tweak is enabled
    if ( $SETTINGS{'require_secure_auth'} ) {
        @REPLACETEXT{ 'fixed_login', 'fixed_plain' } = @REPLACETEXT{ 'secure_login', 'secure_plain' };
    }

    if ( !$SETTINGS{'smarthost_routelist'} || !$SETTINGS{'smarthost_auth_required'} ) {
        $REPLACETEXT{'smarthost_login'} = $REPLACETEXT{'no_smarthost_login'};
    }

    my $replaceinsertregex = join( '|', @REPLACELIST );
    $self->{'rawout'} .= "Exim Replace Regex is: $replaceinsertregex\n" if $self->{'debug'};

    my %MATCHINSERTTEXT;
    $self->load_dir_contents_into_hash( '/usr/local/cpanel/etc/exim/matchcf', [], \%MATCHINSERTTEXT );
    $self->_fill_template_values( \%MATCHINSERTTEXT, \%SETTINGS );

    my $matchinsertregex = join( '|', keys %MATCHINSERTTEXT );
    $self->{'rawout'} .= "Exim Match Insert Regex is: $matchinsertregex\n" if $self->{'debug'};

    my ( $template, $test_cfg ) = $self->build_exim_conf_from_loaded_cfg(
        'CF'                 => \%CF,
        'rawout'             => $self->{'rawout'},
        'config_template'    => $config_template,
        'exim_caps'          => $self->{'exim_caps'},
        'SETTINGS'           => \%SETTINGS,
        'KILLCF'             => \@KILLCF,
        'matchinsertregex'   => $matchinsertregex,
        'insertregex'        => $insertregex,
        'replaceinsertregex' => $replaceinsertregex,
        'MATCHINSERTTEXT'    => \%MATCHINSERTTEXT,
        'INSERTTEXT'         => \%INSERTTEXT,
        'REPLACETEXT'        => \%REPLACETEXT
    );

    my $goodconf = 0;
    if ( $self->{'no_validate'} ) {
        $goodconf = 1;
    }
    else {
        my ( $testfile, $test_fh ) = Cpanel::Rand::get_tmp_file_by_name('/etc/exim.conf.buildtest');    # audit case 46806 ok
        if ($testfile) {
            print {$test_fh} $test_cfg;
            close($test_fh);
        }
        $goodconf = Cpanel::Exim::Config::Check::check_exim_config( $self, $testfile );
        unlink($testfile);
    }

    return (
        'status'           => 1,
        'goodconf'         => $goodconf,
        'acls'             => \%ACLS,
        'cf'               => \%CF,
        'config_template'  => $config_template,
        'eximbin'          => $self->{'eximbin'},
        'eximversion'      => $self->{'eximversion'},
        'exim_caps'        => $self->{'exim_caps'},
        'acl_spam_handler' => $acl_spam_handler,
        'cfg'              => $test_cfg,
        'template'         => $template,
        'settings'         => \%SETTINGS,
        'rawout'           => $self->{'rawout'}
    );
}

sub _use_myexim_cert() {
    return ( -e '/etc/myexim.key' && -e '/etc/myexim.crt' );
}

sub build_exim_conf_from_loaded_cfg ( $self, %OPTS ) {    ## no critic(ProhibitExcessComplexity)

    my $inkill      = 0;
    my $incfkill    = 0;
    my $inblockkill = 0;
    my $test_cfg;
    my $template;
    my $cf;
    my $killregex_str = join( '|', map { '^' . quotemeta($_) . '\s', '^' . quotemeta($_) . '=', '^' . quotemeta($_) . '$' } @{ $OPTS{'KILLCF'} } );
    my $killregex     = qr/$killregex_str/i;

    my $config_template_file = ( -e '/usr/local/cpanel/etc/exim/distconfig/exim.conf.' . $OPTS{'config_template'} ? '/usr/local/cpanel/etc/exim/distconfig/exim.conf.' . $OPTS{'config_template'} : '/etc/exim.conf.' . $OPTS{'config_template'} );

    if ( open( my $template_fh, '<', $config_template_file ) ) {
        while ( readline($template_fh) ) {
            if (m/^\@([^\@]+)\@/) {
                $inblockkill = 0;
                $cf          = $1;

                # Special magic here to add %RETRYBLOCK%
                $test_cfg .= ( $OPTS{'CF'}->{$cf} ? $OPTS{'CF'}->{$cf} : '' ) . "\n\n";
                if ( $cf eq 'RETRYEND' ) { $template .= "%ENDRETRYBLOCK%\n"; $incfkill = 0; }
                $template .= $_;
                if ( $cf eq 'RETRYSTART' ) {
                    $template .= "%BEGINRETRYBLOCK%\n";
                    if ( $OPTS{'CF'}->{'RETRYBLOCK'} ) {
                        $test_cfg .= $OPTS{'CF'}->{'RETRYBLOCK'} . "\n";
                        $inblockkill = 1;
                        $incfkill    = 1;
                    }
                }
            }
            elsif (m/^\%([^\%]+)\%/) {
                $template .= $_;
                $inblockkill = 0;
                my $pushcf = $1;
                my $acf    = $pushcf;
                $acf =~ s/^BEGIN//g;
                $acf =~ s/^END//g;
                if ( $pushcf =~ m/^BEGIN/ ) {
                    if ( defined $OPTS{'CF'}->{$acf} && $OPTS{'CF'}->{$acf} ne '' ) {
                        $incfkill = 1;
                    }
                }
                if ( $pushcf =~ m/^END/ ) {
                    if ( defined $OPTS{'CF'}->{$acf} && $OPTS{'CF'}->{$acf} ne '' ) {
                        $test_cfg .= $OPTS{'CF'}->{$acf} . "\n\n";
                    }
                    $incfkill = 0;
                }
                next;
            }
            else {
                if ( !$self->{'exim_caps'}->{'maildir'} ) {
                    if (m/^\s+quota_directory/) {
                        $self->{'rawout'} .= "[mbox support] removed quota_directory line.\n";
                        next();
                    }
                    if (m/^\s+maildir_use_size_file/) {
                        $self->{'rawout'} .= "[mbox support] removed maildir_use_size_file line.\n";
                        next();
                    }
                    elsif (m/^\s+maildir_tag/) {
                        $self->{'rawout'} .= "[mbox support] removed maildir_tag line.\n";
                        next();
                    }
                    elsif (m/^\s+maildir_quota_/) {
                        $self->{'rawout'} .= "[mbox support] removed maildir_quota_* line.\n";
                        next();
                    }
                    elsif (m/^\s+quota_size_regex/) {
                        $self->{'rawout'} .= "[mbox support] removed quota_size_regex line.\n";
                        next();
                    }
                    elsif (m/^\s+maildir_format/) {
                        $self->{'rawout'} .= "[mbox support] removed maildir_format line.\n";
                        next();
                    }
                    elsif (m/^\s+directory\s*=/) {
                        $self->{'rawout'} .= "[mbox support] switched directory to file= and replaced '/.' with '/' .\n";
                        s/^(\s+)directory\s*=/$1file =/g;
                        s/\/\./\//g;
                        s/\/mail\"/\/mail\/inbox\"/g;
                        s/\/(\$\{local_part\})\"/\/$1\/inbox\"/g;
                    }
                }
                next if $incfkill == 1;
                if ($inblockkill) {
                    if ( !$_ || m/^\s*[^\s\:]+\:/ || m/^\s*$/ ) { $inblockkill = 0; }
                    else                                        { next; }
                }
                if ( $cf && $cf =~ m/ACL/ ) {
                    if (m/^[\s\t]*require[\s\t]*verify[\s\t]*=[\s\t]*([a-z_]+)/) {
                        if ( !$OPTS{'SETTINGS'}->{'senderverify'} && $1 eq 'sender' ) { next; }
                        if ( !$OPTS{'SETTINGS'}->{'callouts'} )                       { s/\/callout//g; }
                    }
                    elsif ( !$self->{'exim_caps'}->{'add_header'} && m/^\s*add_header/ ) {
                        s/^(\s*)add_header/$1message/g;
                    }
                }
                if ( $cf && $cf eq 'CONFIG' ) {
                    if ( !$inkill ) {
                        $inkill = 1 if $_ =~ $killregex;
                    }
                    if ( !$inkill ) {
                        $test_cfg .= $_;
                        $template .= $_;
                    }
                    if ($inkill) {
                        if ( !m/\\\s*$/ ) {
                            $inkill = 0;
                        }
                    }
                }
                else {
                    if ( $OPTS{'matchinsertregex'} && length( $OPTS{'matchinsertregex'} ) > 3 && m/($OPTS{'matchinsertregex'})/ ) {
                        $test_cfg .= "$OPTS{'MATCHINSERTTEXT'}->{$1}\n";
                        $template .= "$OPTS{'MATCHINSERTTEXT'}->{$1}\n";
                    }
                    if ( $OPTS{'insertregex'} && length( $OPTS{'insertregex'} ) > 3 && m/^($OPTS{'insertregex'}):/ ) {
                        my $regexm = $1;

                        my $sections_ref = _parse_router_or_transport_section( $regexm, $OPTS{'INSERTTEXT'}->{$regexm} );
                        foreach my $section ( @{$sections_ref} ) {
                            my @NEEDS      = ( 'boxtrapper', 'maildir' );
                            my $needed_ref = _check_regex( $section->{'text'}, \@NEEDS );
                            my $can_use    = 1;
                            foreach my $need (@NEEDS) {
                                if ( !$self->{'exim_caps'}->{$need} && $needed_ref->{$need} ) {
                                    $self->{'rawout'} .= "Skipping $section->{'name'} entry in $regexm insert as it requires $need and it is disabled or unavailable.\n";
                                    $can_use = 0;
                                }
                            }
                            if ($can_use) {
                                $test_cfg .= "\n" . $section->{'text'} . "\n";
                                $template .= "\n" . $section->{'text'} . "\n";
                            }
                        }
                    }
                    if ( $OPTS{'replaceinsertregex'} && length( $OPTS{'replaceinsertregex'} ) > 3 && m/($OPTS{'replaceinsertregex'}):/ ) {
                        my $regexm = $1;

                        my $sections_ref = _parse_router_or_transport_section( $regexm, $OPTS{'REPLACETEXT'}->{$regexm} );
                        foreach my $section ( @{$sections_ref} ) {
                            my @NEEDS      = ( 'boxtrapper', 'maildir' );
                            my $needed_ref = _check_regex( $section->{'text'}, \@NEEDS );
                            my $can_use    = 1;
                            foreach my $need (@NEEDS) {
                                if ( !$self->{'exim_caps'}->{$need} && $needed_ref->{$need} ) {
                                    $self->{'rawout'} .= "Skipping $section->{'name'} entry in $regexm replace insert as it requires $need and it is disabled or unavailable.\n";
                                    $can_use = 0;
                                }
                            }
                            if ($can_use) {
                                $inblockkill = 1;    #kill block because its a replace
                                $test_cfg .= "\n" . $section->{'text'} . "\n";
                                $template .= "\n" . $section->{'text'} . "\n";
                            }
                        }
                    }

                    next if $inblockkill;

                    $test_cfg .= $_;
                    $template .= $_;

                }
            }
        }
        close($template_fh);
    }
    else {
        return ( "Failed to open $config_template_file", "Failed to open $config_template_file" );
    }

    my $current_block   = 'unknown';
    my $current_section = 'unknown';
    my @test_cfg_lines  = ();
    foreach my $line ( split( /\n/, $test_cfg ) ) {
        if ( $line =~ /^begin\s+(\S+)/ ) {
            $current_section = $1;
        }
        elsif ( $line =~ /^([^ \t :]+):/ ) {
            $current_block = $1;
        }

        if ( $current_section eq 'transports' ) {
            if (
                   $OPTS{'SETTINGS'}->{'rewrite_from'}
                && $OPTS{'SETTINGS'}->{'rewrite_from'} ne 'disable'
                && $current_block !~ m{mailman}          # case CPANEL-5949: This transport happens before discover_sender_information so it cannot be rewritten
                && $current_block !~ m{autowhitelist}    # case CPANEL-5949: This transport happens before discover_sender_information so it cannot be rewritten
            ) {
                if ( $line =~ /^[ \t]+driver[ \t]+=[ \t]+(\S+)/ ) {
                    my $driver = $1;
                    if ( ( $driver eq 'smtp' && $OPTS{'SETTINGS'}->{'rewrite_from'} eq 'remote' ) || $OPTS{'SETTINGS'}->{'rewrite_from'} eq 'all' ) {
                        $line .= "\n  " . <<~'EOS';
                        #   add headers
                            headers_rewrite = * ${perl{get_headers_rewrite}} f
                            headers_add = "${perl{get_headers_rewritten_notice}}"
                        EOS
                        chomp $line;
                    }
                }
            }
            if (   $OPTS{'SETTINGS'}->{'smarthost_routelist'}
                && $OPTS{'SETTINGS'}->{'smarthost_auth_required'}
                && $current_block =~ m{^(?:dkim_)?remote_(?:forwarded_)?smtp} ) {
                if ( $line =~ /^[ \t]+driver[ \t]+=[ \t]+(\S+)/ ) {
                    my $driver = $1;
                    if ( $driver eq 'smtp' ) {
                        $line .= "\n" . <<~EOS;
                          # force authentication when delivering to smarthost:
                          hosts_require_auth = +smarthosts
                          hosts_require_tls  = +smarthosts
                        EOS
                        chomp $line;
                    }
                }
            }
            if ( $OPTS{'SETTINGS'}->{'hosts_avoid_pipelining'} && $current_block =~ m{^(?:dkim_)?remote_(?:forwarded_)?smtp} ) {
                if ( $line =~ /^[ \t]+driver[ \t]+=[ \t]+(\S+)/ ) {
                    my $driver = $1;
                    if ( $driver eq 'smtp' ) {
                        $line .= "\n" . <<~EOS;
                          # Disable pipelining for all hosts
                          hosts_avoid_pipelining = *
                        EOS
                        chomp $line;
                    }
                }
            }
            if ( !$self->{'exim_caps'}->{'force_command'} ) {
                if ( $line =~ m/^[ \t]*force_command/ ) {
                    $line = "#$line   -- force_command not compiled into this version of exim";
                }
            }

        }
        elsif ( $current_section eq 'routers' ) {
            if ( $OPTS{'SETTINGS'}->{'smarthost_routelist'} ) {
                if ( $line =~ s/^(\s*)(driver\s*=\s*)(?:dnslookup|ipliteral)(.*)/$1$2manualroute$3/ ) {
                    $line .= "\n$1route_list = $OPTS{'SETTINGS'}->{'smarthost_routelist'}";
                }
            }
        }

        push @test_cfg_lines, $line;
    }
    $test_cfg = join( "\n", @test_cfg_lines );

    # Why go through the file again? This loop does almost the same thing as the above.
    my @template_lines = ();
    $current_block   = 'unknown';
    $current_section = 'unknown';
    foreach my $line ( split( /\n/, $template ) ) {
        if ( $line =~ /^begin\s+(\S+)/ ) {
            $current_section = $1;
        }
        elsif ( $line =~ /^([^ \t :]+):/ ) {
            $current_block = $1;
        }

        if ( $current_section eq 'transports' ) {
            if (
                   $OPTS{'SETTINGS'}->{'rewrite_from'}
                && $OPTS{'SETTINGS'}->{'rewrite_from'} ne 'disable'
                && $current_block !~ m{mailman}          # case CPANEL-5949: This transport happens before discover_sender_information so it cannot be rewritten
                && $current_block !~ m{autowhitelist}    # case CPANEL-5949: This transport happens before discover_sender_information so it cannot be rewritten
            ) {
                if ( $line =~ /^[ \t]+driver[ \t]+=[ \t]+(\S+)/ ) {
                    my $driver = $1;
                    if ( ( $driver eq 'smtp' && $OPTS{'SETTINGS'}->{'rewrite_from'} eq 'remote' ) || $OPTS{'SETTINGS'}->{'rewrite_from'} eq 'all' ) {
                        $line .= "\n" . <<~'EOS';
                            #   add headers
                            headers_rewrite = * ${perl{get_headers_rewrite}} f
                            headers_add = "${perl{get_headers_rewritten_notice}}";
                        EOS
                        chomp $line;
                    }
                }
            }
            if (   $OPTS{'SETTINGS'}->{'smarthost_routelist'}
                && $OPTS{'SETTINGS'}->{'smarthost_auth_required'}
                && $current_block =~ m{^(?:dkim_)?remote_(?:forwarded_)?smtp} ) {
                if ( $line =~ /^[ \t]+driver[ \t]+=[ \t]+(\S+)/ ) {
                    my $driver = $1;
                    if ( $driver eq 'smtp' ) {
                        $line .= "\n" . <<~EOS;
                          # force authentication when delivering to smarthost:
                          hosts_require_auth = +smarthosts
                          hosts_require_tls  = +smarthosts
                        EOS
                        chomp $line;
                    }
                }
            }
            if ( $OPTS{'SETTINGS'}->{'hosts_avoid_pipelining'} && $current_block =~ m{^(?:dkim_)?remote_(?:forwarded_)?smtp} ) {
                if ( $line =~ /^[ \t]+driver[ \t]+=[ \t]+(\S+)/ ) {
                    my $driver = $1;
                    if ( $driver eq 'smtp' ) {
                        $line .= "\n" . <<~EOS;
                          # Disable pipelining for all hosts
                          hosts_avoid_pipelining = *
                        EOS
                        chomp $line;
                    }
                }
            }
        }
        elsif ( $current_section eq 'routers' ) {
            if ( $OPTS{'SETTINGS'}->{'smarthost_routelist'} ) {
                if ( $line =~ s/^(\s*)(driver\s*=\s*)(?:dnslookup|ipliteral)(.*)/$1$2manualroute$3/ ) {
                    $line .= "\n$1route_list = $OPTS{'SETTINGS'}->{'smarthost_routelist'}";
                }
            }
        }
        push @template_lines, $line;
    }
    $template = join( "\n", @template_lines );

    # Allow substitutions to “call” other substitutions:
    while ( $test_cfg =~ m/%CPANEL-([^%]+?)%/ ) {
        my $replacement = $CPANEL_SUBSTITUTION{$1} || do {
            die "Bad substitution: $1";
        };

        substr( $test_cfg, $-[0], $+[0] - $-[0] ) = $replacement;    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
    }

    return ( $template, $test_cfg );
}

sub _check_regex ( $regexm, $needs_list ) {

    $regexm =~ s/^\s*#.*//gm;    #do not look at comments (multi-line)

    my %NEEDS;
    foreach my $need ( @{$needs_list} ) {
        $NEEDS{$need} = ( $regexm =~ m/$need/i ? 1 : 0 );
    }
    return \%NEEDS;
}

sub _slurpout ( $self, $file, $fh ) {
    my $ilock = Cpanel::SafeFile::safeopen( \*IF, '<', $file );
    if ( !$ilock ) {
        $self->warn("Could not read from $file");
        return;
    }
    while ( readline( \*IF ) ) {
        print {$fh} $_;
    }
    return Cpanel::SafeFile::safeclose( \*IF, $ilock );
}

sub ensure_setup ($self) {
    return Cpanel::FileUtils::TouchFile::touchfile('/etc/trustedmailhosts');    # Prevent Exim from warning about a missing file
}

sub run_script ( $self, $script_id, $status = undef ) {

    if ( -x '/usr/local/cpanel/scripts/' . $script_id . 'buildeximconf' ) {
        my @RUN = (
            '/usr/local/cpanel/scripts/' . $script_id . 'buildeximconf',
            '--version',    $self->{'eximversion'},
            '--hasdkim',    1,
            '--hasmaildir', $self->{'exim_caps'}->{'maildir'},
            @ARGV
        );
        if ($status) { push @RUN, '--status', $status }
        system @RUN;
    }
    return;
}

sub _merge_array_into_hash_with_fixed_value ( $array_ref, $hash_ref, $value ) {
    foreach my $element ( @{$array_ref} ) {
        $hash_ref->{$element} = $value;
    }
    return;
}

sub install_virgin_config_if_missing ( $self, $config_template ) {

    if ( !-e '/etc/exim.conf' ) {
        open( my $cf_fh,       '>', '/etc/exim.conf' );
        open( my $template_fh, '<', '/etc/exim.conf.' . $config_template );
        while ( readline($template_fh) ) {
            if ( !m/^\@[^\@]+\@/ && !m/^\%[^\%]+\%/ ) {
                print {$cf_fh} $_;
            }
        }
        close $cf_fh;
        close $template_fh;
    }
    return;
}

sub load_dir_contents_into_hash ( $self, $dir, $skip_array_ref, $hash_ref ) {

    my %DIRLIST = Cpanel::Dir::Loader::load_dir_as_hash_with_value( $dir, 1 );

    foreach my $file ( sort keys %DIRLIST ) {
        next if ( -B $dir . '/' . $file || -d _ );
        next if ( grep( /^\Q$file\E/, @{$skip_array_ref} ) );    #replaced by other means
        push( @{$skip_array_ref}, $file );

        my $file_to_read;
        if ( $self->{'exim_caps'}->{'dovecot'} && -e $dir . '/dovecot/' . $file ) {
            $file_to_read = $dir . '/dovecot/' . $file;
        }
        elsif ( -e $dir . '/dkim/' . $file ) {
            $file_to_read = $dir . '/dkim/' . $file;
        }
        elsif ( $self->{'exim_caps'}->{'mailman'} && -e $dir . '/mailman/' . $file ) {
            $file_to_read = $dir . '/mailman/' . $file;
        }
        elsif ( $self->{'exim_caps'}->{'archive'} && -e $dir . '/archive/' . $file ) {
            $file_to_read = $dir . '/archive/' . $file;
        }
        elsif ( $self->{'exim_caps'}->{'rewrite_from_remote'} && -e $dir . '/rewrite_from_remote/' . $file ) {
            $file_to_read = $dir . '/rewrite_from_remote/' . $file;
        }
        elsif ( $self->{'exim_caps'}->{'rewrite_from_all'} && -e $dir . '/rewrite_from_all/' . $file ) {
            $file_to_read = $dir . '/rewrite_from_all/' . $file;
        }
        elsif ( $self->{'exim_caps'}->{'no_forward_outbound_spam_over_int'} && -e $dir . '/no_forward_outbound_spam_over_int/' . $file ) {
            $file_to_read = $dir . '/no_forward_outbound_spam_over_int/' . $file;
        }
        elsif ( $self->{'exim_caps'}->{'no_forward_outbound_spam'} && -e $dir . '/no_forward_outbound_spam/' . $file ) {
            $file_to_read = $dir . '/no_forward_outbound_spam/' . $file;
        }
        elsif ( $self->{'exim_caps'}->{'srs'} && -e $dir . '/srs/' . $file ) {
            $file_to_read = $dir . '/srs/' . $file;
        }
        elsif ( $self->{'exim_caps'}->{'reject_overquota_at_smtp_time'} && -e $dir . '/reject_overquota_at_smtp_time/' . $file ) {
            $file_to_read = $dir . '/reject_overquota_at_smtp_time/' . $file;
        }
        else {
            $file_to_read = $dir . '/' . $file;
        }
        if ( open( my $file_fh, $file_to_read ) ) {

            #print "==> Loading $file_to_read\n";
            local $/;
            $hash_ref->{$file} .= readline($file_fh);
            $hash_ref->{$file} =~ s/[\r\n]+$//g;
            close($file_fh);
        }
    }

    return;
}

sub check_acls_for_content ( $self, $cf_ref ) {
    my $test_acl;
    my $in_acl;
    my %HAS_ACL_CONTENT;
    my %ACL_CONTENT;
    foreach ( split( /\n/, ( $cf_ref->{'BEGINACL'} || '' ) . "\n" . $cf_ref->{'ACLBLOCK'} . "\n" . ( $cf_ref->{'ENDACL'} || '' ) ) ) {
        if (/^\s*([^\s\:]+):\s*$/m) {
            $test_acl                   = $1;
            $HAS_ACL_CONTENT{$test_acl} = 0;
            $in_acl                     = 1;
        }
        elsif ( /^\s*\#/ || /^\s*$/ ) {
            next;
        }
        elsif ($in_acl) {
            $ACL_CONTENT{$test_acl} .= $_;
            $HAS_ACL_CONTENT{$test_acl} = 1;
        }
    }
    return ( \%ACL_CONTENT, \%HAS_ACL_CONTENT );
}

sub insert_acl_blocks_into_cf ( $self, $cf_ref, $acl_block_ref, $enabledacls_ref, $settings_ref ) {    ## no critic qw(Subroutines::ProhibitExcessComplexity)

    #
    # If we have mailman and exiscan available then we can enable these acl blocks
    #

    my %SKIP_ACL_BLOCKS = ( 'ACL_RECIPIENT_MAILMAN_BLOCK' => 1, 'ACL_EXISCAN_BLOCK' => 1, 'ACL_EXISCANALL_BLOCK' => 1 );
    delete $SKIP_ACL_BLOCKS{'ACL_RECIPIENT_MAILMAN_BLOCK'} if $self->{'exim_caps'}->{'mailman'};
    if ( $self->{'exim_caps'}->{'exiscan'} ) {
        if ( $settings_ref->{'exiscanall'} ) {
            delete $SKIP_ACL_BLOCKS{'ACL_EXISCANALL_BLOCK'};
        }
        else {
            delete $SKIP_ACL_BLOCKS{'ACL_EXISCAN_BLOCK'};
        }
    }

    foreach my $aclblock ( keys %{$acl_block_ref} ) {
        next if exists $SKIP_ACL_BLOCKS{$aclblock};

        my @ENABLEDACLS;
        my %ACLINSERTS;
        $ACLINSERTS{$aclblock} = '';

        my @sorted_acls = _sort_acl_inserts( $acl_block_ref->{$aclblock} );

        foreach my $acl (@sorted_acls) {
            my $acl_cf_value = $enabledacls_ref->{$acl};
            my $acl_name     = $acl;
            $acl_name =~ s/\.dry_run$//;
            if ( $acl_name =~ /_malware_/i && !$self->{'exim_caps'}->{'exiscan'} ) {
                $self->{'rawout'} .= "ACL INSERT: $acl_name is disabled because exim is missing exiscan support (install clamav)\n";
                next;
            }

            if ( $acl_cf_value || $self->{'fetch_acls'} ) {
                my $acl_slurp = Cpanel::LoadFile::loadfile( "$acls_dir/" . $aclblock . '/' . $acl );
                push @ENABLEDACLS, $acl if defined $acl_slurp && $acl_slurp ne '';
                $acl_slurp =~ s{\[%\s*VALUE\s*%]}{$acl_cf_value}g;
                if ( $self->{'fetch_acls'} ) {
                    my $editable = ( $acl =~ /custom_/ ? 1 : 0 );
                    $ACLINSERTS{$aclblock} .= "[\@ BEGIN INSERT $acl_name ENABLED=$acl_cf_value EDITABLE=$editable \@]\n" . ( $acl_slurp eq '' ? '' : "$acl_slurp\n" ) . "[\@ END INSERT $acl_name ENABLED=$acl_cf_value EDITABLE=$editable \@]\n";
                }
                else {
                    if ( $acl_name eq 'greylisting' && !Cpanel::GreyList::Config::loadconfig()->{'spf_bypass'} ) {

                        # TODO: see if there is a better way to do this...
                        my @lines = grep { $_ !~ m/^.*spf\s.*$/ } ( split /\n/, $acl_slurp );
                        $acl_slurp = join( "\n", @lines ) . "\n\n";
                    }
                    if ( $acl_name eq 'delay_unknown_hosts' ) {
                        $acl_slurp =~ s/\s+\+greylist_trusted_netblocks\s+://     if !$settings_ref->{'dont_delay_greylisting_trusted_hosts'};
                        $acl_slurp =~ s/\s+\+greylist_common_mail_providers\s+:// if !$settings_ref->{'dont_delay_greylisting_common_mail_providers'};
                    }
                    $ACLINSERTS{$aclblock} .= "# BEGIN INSERT $acl_name\n$acl_slurp\n# END INSERT $acl_name\n" if $acl_slurp;
                }
            }
        }

        if ( @ENABLEDACLS && $self->{'debug'} ) {
            $self->{'rawout'} .= "Enabled ACL options in block $aclblock: ";
            $self->{'rawout'} .= join( '|', @ENABLEDACLS );
            $self->{'rawout'} .= "\n";
        }

        $self->_fill_template_values( \%ACLINSERTS, $settings_ref );

        foreach my $aclblock ( keys %ACLINSERTS ) {
            ##
            ## If exim.conf has qr/_[ODU]/ anywhere in it the parser will call
            ## macros_create_builtin and make exim.conf parsing massively slower
            ## In testing it was 3x slower
            ##
            ##  0m0.021s -> 0m0.066s
            ##
            my $macros_create_builtin_safe_aclblock = $aclblock =~ s/_/-/gr;
            my $begin                               = $self->{'fetch_acls'} ? "[\@ BEGIN BLOCK $aclblock \@]" : "#BEGIN $macros_create_builtin_safe_aclblock";
            my $end                                 = $self->{'fetch_acls'} ? "[\@ END BLOCK $aclblock \@]"   : "#END $macros_create_builtin_safe_aclblock";
            if ( $cf_ref->{'ACLBLOCK'} =~ s/^\s*\[\s*\%\s*\Q$aclblock\E\s*\%\s*\]/\n$begin\n$ACLINSERTS{$aclblock}\n$end/gm ) {

                #insert ok
            }
            elsif ( $ACLINSERTS{$aclblock} ) {    #only complain if we actually wanted to insert something

                $self->warn("ACL insert failed: $aclblock is missing from the ACLBLOCK config section");
            }
        }
    }
    return;
}

sub load_settings_acls_filters_from_local_conf ( $self, $settings_ref, $acls_ref, $filters_ref, $file = 'localopts' ) {    ## no critic qw(ProhibitManyArgs)

    if ( open( my $localopts_fh, '<', ( $self->{$file} ? $self->{$file} : '/etc/exim.conf.localopts' ) ) ) {
        while ( readline($localopts_fh) ) {
            chomp();
            next if !length;
            my ( $opt, $value ) = split( /=/, $_, 2 );

            # Case 38522, skip if no value is defined and opt is not acl/filter
            if ( !defined $value || ( $value = Cpanel::StringFunc::Trim::ws_trim($value) ) eq '' ) {
                if ( $opt =~ m/^(?:acl|filter)_\S+/ ) {
                    $value = 0;
                }
                elsif ( $opt eq 'systemfilter' ) {

                    # difference between explicitely disabled configuration
                    #   and missing value in configuration ( same as exists vs defined )
                    $value = 'disabled';
                }
                else {
                    $self->debug("No value is defined for $opt. This line is skipped in /etc/exim.conf.localopts");
                    next;
                }
            }

            if ( $opt !~ m/spam_score_over_\d+$/ && $opt =~ m/^acl_(\S+)/ ) {
                $acls_ref->{ $1 . '.dry_run' } = int $value if $self->{'acl_dry_run'};
                $acls_ref->{$1} = int $value;
            }
            elsif ( $opt !~ m/spam_score_over_\d+$/ && $opt =~ m/^filter_(\S+)/ ) {
                $filters_ref->{$1} = int $value;
            }
            else {
                $settings_ref->{$opt} = ( $value =~ /^[0-9]+$/ ? int $value : $value );
            }
        }
        close($localopts_fh);
    }
    return;
}

sub generate_cpanel_system_filter ( $self, $filters_ref ) {

    my $FILTER_BUILD_FILE = $FILTER_TARGET_FILE . '.build';

    $self->{'rawout'} .= "Enabled system filter options: " if $self->{'debug'};
    my @FLOPTS;
    my $flock = Cpanel::SafeFile::safeopen( \*ANTIV, '>', $FILTER_BUILD_FILE );
    if ( !$flock ) {
        $self->warn("Could not write to $FILTER_BUILD_FILE");
        return;
    }

    $self->_slurpout( $FILTER_SOURCE_DIR . '/default', \*ANTIV );

    foreach my $filter ( sort keys %{$filters_ref} ) {
        my $filter_val = $filters_ref->{$filter};
        next if ( !$filter_val );
        push @FLOPTS, $filter;

        my $ilock = Cpanel::SafeFile::safeopen( \*IF, '<', $FILTER_SOURCE_DIR . '/options/' . $filter );
        if ( !$ilock ) {
            my $err = "Could not read from $FILTER_SOURCE_DIR/options/$filter: This filter will be skipped";
            $self->warn($err);
            $self->{'rawout'} .= "$err\n";

            # case CPANEL-23751: skip missing filters instead of failing
            next;
        }
        local $/;
        my $filter_text = readline \*IF;
        Cpanel::SafeFile::safeclose( \*IF, $ilock );

        $filter_text =~ s{\[%\s*VALUE\s*%]}{$filter_val}g;

        $filter_text =~ s/^\n+//g;
        $filter_text =~ s/\n+$//g;
        print ANTIV "\n# BEGIN - Included from $FILTER_SOURCE_DIR/options/$filter\n# (Use the Basic Editor in the Exim Configuration Manager in WHM to change)\n# or manually edit /etc/exim.conf.localopts and run /scripts/buildeximconf\n" . $filter_text . "\n# END - Included from $FILTER_SOURCE_DIR/options/$filter\n";
    }
    Cpanel::SafeFile::safeclose( \*ANTIV, $flock );
    $self->{'rawout'} .= join( '|', @FLOPTS ) if $self->{'debug'};
    $self->{'rawout'} .= "\n";
    if ( !rename( $FILTER_BUILD_FILE, $FILTER_TARGET_FILE ) ) {
        $self->warn("The system failed to install $FILTER_BUILD_FILE as $FILTER_TARGET_FILE because of an error: $!");
        return;
    }
    return 1;
}

sub load_local_exim_config ( $self, $cf_ref, $killcf_ref ) {

    if ( open( my $cfg_fh, '<', ( $self->{'local'} ? $self->{'local'} : '/etc/exim.conf.local' ) ) ) {
        my $cf_section;
        while ( readline($cfg_fh) ) {
            if (/^\@([^\@]+)\@/) {
                $cf_section = $1;
            }
            elsif (/^\%([^\%]+)\%/) {
                $cf_section = $1;
            }
            elsif ($cf_section) {
                if ( $cf_section eq 'CONFIG' && /=[\t\s]*$/ ) {
                    my $optname = ( split( /=/, $_ ) )[0];
                    $optname =~ s/^\s+|\s+$//g;
                    push( @{$killcf_ref}, $optname );
                    next();
                }
                $cf_ref->{$cf_section} .= $_;
            }
        }
        close($cfg_fh);
    }
    foreach my $cf_section ( keys %{$cf_ref} ) {
        $cf_ref->{$cf_section} =~ s/^[\n\r]*|[\n\r]*$//g;
    }
    return;
}

sub build_and_install_exim_pl ( $self, $exim_pl_path = undef ) {
    $exim_pl_path //= '/etc/exim.pl.local';

    my $ulc    = q[/usr/local/cpanel];
    my $tmpdir = qq[$ulc/tmp];

    Cpanel::SafeDir::MK::safemkdir( $tmpdir, 0755 ) unless -d $tmpdir;

    my $tmp_rel_path = 'tmp/exim.local.build.pl';
    my $tmp_path     = "$tmpdir/exim.local.build.pl";

    my $has_service_auth = 0;
    my %PERLTEXT;
    $self->load_dir_contents_into_hash( '/usr/local/cpanel/etc/exim/perl', [], \%PERLTEXT );
    $self->{'rawout'} .= "Exim Perl Load List is: " . join( '|', keys %PERLTEXT ) . "\n" if $self->{'debug'};

    my $build_lock;

    try {
        # The exim.pl.local build logic is guarded with a lock due to the use of fixed temporary paths.
        $build_lock = Cpanel::SafeFile::safelock($tmp_path);
        unlink( $tmp_path, "$tmp_path.static" );
        sysopen( my $expll_fh, $tmp_path, Cpanel::Fcntl::or_flags(qw( O_WRONLY O_TRUNC O_CREAT )), 0755 ) || $self->logger->panic("Failed to open $tmp_path: $!");

        foreach my $perl ( sort keys %PERLTEXT ) {
            if ( !$has_service_auth && $PERLTEXT{$perl} =~ /exim:serviceauth=1/ ) {
                $has_service_auth = 1;
            }
            print {$expll_fh} $PERLTEXT{$perl} . "\n";
        }
        print {$expll_fh} "\n1;\n";
        close($expll_fh);

        my $perl_out = Cpanel::SafeRun::Errors::saferunallerrors( "/usr/local/cpanel/3rdparty/bin/perl", "-Mstrict", "-c", $tmp_path );
        if ( $? != 0 ) {
            my $why      = Cpanel::ChildErrorStringifier->new($?)->autopsy();
            my $perl_msg = "Warning: Failed to build a $exim_pl_path does not pass use strict: $why: $perl_out\n";
            $self->logger->invalid($perl_msg);
            $self->{'rawout'} .= $perl_msg;
        }

        my $pkg_out = do {
            my $chdir = Cpanel::Chdir->new($ulc);    # required for perlpkg
            local $ENV{'USE_CPANEL_PERL_FOR_PERLSTATIC'} = 1;
            Cpanel::SafeRun::Errors::saferunallerrors( "/usr/local/cpanel/3rdparty/bin/perl", "/usr/local/cpanel/bin/perlpkg", '--no-try-tiny', '--no-http-tiny', '--no-file-path-tiny', $tmp_rel_path );
        };

        if ( $? == 0 && -e $tmp_path . '.static' ) {

            # case CPANEL-20331: use rename into place to install these are mail delivery is so frequent that
            # it can have a transient error while the file was being written.
            Cpanel::FileUtils::Write::overwrite( $exim_pl_path, Cpanel::LoadFile::load( $tmp_path . '.static' ), 0644 );
        }
        else {
            my $why      = Cpanel::ChildErrorStringifier->new($?)->autopsy();
            my $perl_msg = "Warning: perlpkg could not create an optimize $exim_pl_path: $why: $pkg_out\n";
            $self->warn($perl_msg);
            $self->{'rawout'} .= $perl_msg;

            # case CPANEL-20331: use rename into place to install these are mail delivery is so frequent that
            # it can have a transient error while the file was being written.
            Cpanel::FileUtils::Write::overwrite( $exim_pl_path, Cpanel::LoadFile::load($tmp_path), 0644 );
        }

        $self->{'rawout'} .= "$exim_pl_path installed!\n";

        if ($has_service_auth) {
            Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/exim_service_auth_enable');
        }
        else {
            unlink('/var/cpanel/exim_service_auth_enable');
        }

        # Remove all the old @INCs for perl versions we no longer use
        Cpanel::StringFunc::Replace::regsrep( '/etc/exim.pl', '^(\s*if\s*\(\-e\s*\"[^\"]+\"\)\s*\{push\(\@INC\,\"[^\"]+\"\)\;\})', '#$1' );
    }
    catch { die $_ }
    finally {
        if ($build_lock) {
            unlink( $tmp_path, "$tmp_path.static" );
            Cpanel::SafeFile::safeunlock($build_lock);
        }
    };

    return 1;

}

sub setup_spamassassin_handling {

    # No longer used.  Remove the file
    # since its just cruft at this point
    # as we always call spamassasin via
    # the acl system in exim.

    if ( -e '/etc/exim.aclspam' ) {
        unlink('/etc/exim.aclspam');
    }
    return;
}

sub create_custom_acl_files ($self) {
    return if !-d $acls_dir;

    my %custom_acl_files_for_block = (
        'ACL_SMTP_SMTP_VRFY_BLOCK' => [
            'custom_begin_smtp_smtp_vrfy',
            'custom_end_smtp_smtp_vrfy',
        ],
        'ACL_PRE_SPAM_SCAN' => [
            'custom_begin_pre_spam_scan',
            'custom_end_pre_spam_scan',
        ],
        'ACL_MAILAUTH_BLOCK' => [
            'custom_begin_mailauth',
            'custom_end_mailauth',
        ],
        'ACL_SMTP_MAILAUTH_BLOCK' => [
            'custom_begin_smtp_mailauth',
            'custom_end_smtp_mailauth',
        ],
        'ACL_NOT_SMTP_START_BLOCK' => [
            'custom_end_not_smtp_start',
            'custom_begin_not_smtp_start',
        ],
        'ACL_SPAM_BLOCK' => [
            'custom_end_spam',
            'custom_begin_spam',
        ],
        'ACL_EXISCANALL_BLOCK' => [
            'custom_begin_exiscanall',
            'custom_end_exiscanall',
        ],
        'ACL_EXISCAN_BLOCK' => [
            'custom_begin_exiscan',
            'custom_end_exiscan',
        ],
        'ACL_RECP_VERIFY_BLOCK' => [
            'custom_begin_recp_verify',
            'custom_end_recp_verify',
        ],
        'ACL_SMTP_HELO_BLOCK' => [
            'custom_begin_smtp_helo',
            'custom_end_smtp_helo',
        ],
        'ACL_SMTP_HELO_POST_BLOCK' => [
            'custom_begin_smtp_helo_post',
            'custom_end_smtp_helo_post',
        ],
        'ACL_SMTP_DKIM_BLOCK' => [
            'custom_end_smtp_dkim',
            'custom_begin_smtp_dkim',
        ],
        'ACL_RATELIMIT_SPAM_BLOCK' => [
            'custom_begin_ratelimit_spam',
            'custom_end_ratelimit_spam',
        ],
        'ACL_IDENTIFY_SENDER_BLOCK' => [
            'custom_begin_identify_sender',
            'custom_end_identify_sender',
        ],
        'ACL_RCPT_HARD_LIMIT_BLOCK' => [
            'custom_begin_rcpt_hard_limit',
            'custom_end_rcpt_hard_limit',
        ],
        'ACL_PRE_RECIPIENT_BLOCK' => [
            'custom_end_pre_recipient',
            'custom_begin_pre_recipient',
        ],
        'ACL_RECIPIENT_BLOCK' => [
            'custom_end_recipient',
            'custom_begin_recipient',
        ],
        'ACL_RBL_BLOCK' => [
            'custom_end_rbl',
            'custom_begin_rbl',
        ],
        'ACL_NOTQUIT_BLOCK' => [
            'custom_end_notquit',
            'custom_begin_notquit',
        ],
        'ACL_RECIPIENT_POST_BLOCK' => [
            'custom_begin_recipient_post',
            'custom_end_recipient_post',
        ],
        'ACL_TRUSTEDLIST_BLOCK' => [
            'custom_begin_trustedlist',
            'custom_end_trustedlist',
        ],
        'ACL_SMTP_PREDATA_BLOCK' => [
            'custom_begin_smtp_predata',
            'custom_end_smtp_predata',
        ],
        'ACL_NOT_SMTP_BLOCK' => [
            'custom_end_not_smtp',
            'custom_begin_not_smtp',
        ],
        'ACL_MAIL_PRE_BLOCK' => [
            'custom_begin_mail_pre',
            'custom_end_mail_pre',
        ],
        'ACL_SPAM_SCAN_BLOCK' => [
            'custom_end_spam_scan',
            'custom_begin_spam_scan',
        ],
        'ACL_POST_SPAM_SCAN_CHECK_BLOCK' => [
            'custom_begin_post_spam_scan_check',
            'custom_end_post_spam_scan_check',
        ],
        'ACL_SPAM_SCAN_CHECK_BLOCK' => [
            'custom_end_spam_scan_check',
            'custom_begin_spam_scan_check',
        ],
        'ACL_CHECK_MESSAGE_PRE_BLOCK' => [
            'custom_end_check_message_pre',
            'custom_begin_check_message_pre',
        ],
        'ACL_RCPT_SOFT_LIMIT_BLOCK' => [
            'custom_begin_rcpt_soft_limit',
            'custom_end_rcpt_soft_limit',
        ],
        'ACL_SMTP_QUIT_BLOCK' => [
            'custom_end_smtp_quit',
            'custom_begin_smtp_quit',
        ],
        'ACL_RATELIMIT_BLOCK' => [
            'custom_begin_ratelimit',
            'custom_end_ratelimit',
        ],
        'ACL_POST_RECP_VERIFY_BLOCK' => [
            'custom_end_post_recp_verify',
            'custom_begin_post_recp_verify',
        ],
        'ACL_CONNECT_BLOCK' => [
            'custom_end_connect',
            'custom_begin_connect',
        ],
        'ACL_MAIL_BLOCK' => [
            'custom_end_mail',
            'custom_begin_mail',
        ],
        'ACL_MAIL_POST_BLOCK' => [
            'custom_end_mail_post',
            'custom_begin_mail_post',
        ],
        'ACL_CONNECT_POST_BLOCK' => [
            'custom_begin_connect_post',
            'custom_end_connect_post',
        ],
        'ACL_SMTP_ETRN_BLOCK' => [
            'custom_end_smtp_etrn',
            'custom_begin_smtp_etrn',
        ],
        'ACL_SMTP_AUTH_BLOCK' => [
            'custom_end_smtp_auth',
            'custom_begin_smtp_auth',
        ],
        'ACL_NOT_SMTP_MIME_BLOCK' => [
            'custom_end_not_smtp_mime',
            'custom_begin_not_smtp_mime',
        ],
        'ACL_CHECK_MESSAGE_POST_BLOCK' => [
            'custom_end_check_message_post',
            'custom_begin_check_message_post',
        ],
        'ACL_SMTP_STARTTLS_BLOCK' => [
            'custom_end_smtp_starttls',
            'custom_begin_smtp_starttls',
        ],
        'ACL_RECIPIENT_MAILMAN_BLOCK' => [
            'custom_end_recipient_mailman',
            'custom_begin_recipient_mailman',
        ],
        'ACL_SMTP_MIME_BLOCK' => [
            'custom_end_smtp_mime',
            'custom_begin_smtp_mime',
        ],
        'ACL_OUTGOING_NOTSMTP_CHECKALL_BLOCK' => [
            'custom_end_outgoing_notsmtp_checkall',
            'custom_begin_outgoing_notsmtp_checkall',
        ],
        'ACL_OUTGOING_SMTP_CHECKALL_BLOCK' => [
            'custom_end_outgoing_smtp_checkall',
            'custom_begin_outgoing_smtp_checkall',
        ],
    );

    while ( my ( $block, $files ) = each %custom_acl_files_for_block ) {

        my $dir = "$acls_dir/$block";
        if ( !-e $dir ) {
            if ( !Cpanel::SafeDir::MK::safemkdir($dir) ) {
                $self->warn("Unable to initialize $dir");
                next;
            }
        }

        for my $file (@$files) {
            $file = "$dir/$file";
            if ( !-e $file ) {
                Cpanel::FileUtils::TouchFile::touchfile($file)
                  || $self->warn("Unable to initialize $file");
            }
        }
    }

    return 1;
}

sub _parse_router_or_transport_section ( $rtname, $txt ) {

    my @sections;
    my $section_text;
    my $section_name;
    foreach my $line ( split( m/\n/, $txt ) ) {
        if ( $line =~ m/^\s*([^\:\s]+)\s*:\s*$/ ) {
            if ($section_name) {
                push @sections, { 'name' => $section_name, 'text' => $section_text };
                $section_text = '';
            }
            $section_name = $1;
        }
        $section_text .= $line . "\n";
    }
    push @sections, { 'name' => $section_name, 'text' => $section_text } if $section_text && $section_text =~ m/\n/;
    return \@sections;
}

sub _sort_acl_inserts ($acls) {
    return (
        ( sort ( grep { $_ =~ m/^custom_begin/ } @$acls ) ),
        ( sort ( grep { $_ =~ m/^begin_/ } @$acls ) ),
        ( sort ( grep { $_ !~ m/^custom_(?:begin|end)/ && $_ !~ m/^(?:begin|end)_/ } @$acls ) ),
        ( sort ( grep { $_ =~ m/^end_/ } @$acls ) ),
        ( sort ( grep { $_ =~ m/^custom_end/ } @$acls ) ),
    );
}

sub configure_outgoing_spam_scanning() {
    my $eximscanuser = _get_eximscanner_user();
    return 0 if $eximscanuser eq 'nobody';

    my ( $eximscanuser_uid, $eximscanuser_gid, $eximscanuser_homedir ) = ( Cpanel::PwCache::getpwnam($eximscanuser) )[ 2, 3, 7 ];

    if ( !-e $eximscanuser_homedir ) {
        mkdir( $eximscanuser_homedir, 0700 ) || die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ path => $eximscanuser_homedir, error => $! ] );
        chown $eximscanuser_uid, $eximscanuser_gid, $eximscanuser_homedir or die Cpanel::Exception::create( 'IO::ChownError', [ path => [$eximscanuser_homedir], uid => $eximscanuser_uid, gid => $eximscanuser_gid, error => $! ] );
    }
    elsif ( -d $eximscanuser_homedir ) {
        Cpanel::FileUtils::Access::ensure_mode_and_owner( $eximscanuser_homedir, 0700, $eximscanuser );
    }

    my $prefs_dir  = "$eximscanuser_homedir/.spamassassin";
    my $prefs_file = "$prefs_dir/user_prefs";
    if ( !-e $prefs_file ) {
        my $template = Cpanel::LoadFile::load("$Cpanel::ConfigFiles::CPANEL_ROOT/etc/cpaneleximscanner_user_prefs");
        Cpanel::AccessIds::ReducedPrivileges::call_as_user(
            sub {
                if ( !-e $prefs_dir ) {
                    mkdir( $prefs_dir, 0700 ) || die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ path => $prefs_dir, error => $! ] );
                }
                Cpanel::FileUtils::Write::overwrite_no_exceptions( $prefs_file, $template, 0644 ) || die Cpanel::Exception::create( 'IO::FileWriteError', [ path => $prefs_file, error => $! ] );
                return 1;
            },
            $eximscanuser
        );
    }

    return 1;
}

sub _get_eximscanner_user() {
    my $eximscanuser = 'nobody';

    if ( Cpanel::PwCache::getpwnam('cpaneleximscanner') ) {
        $eximscanuser = 'cpaneleximscanner';
    }

    return $eximscanuser;
}

sub _fill_template_values ( $self, $blocks, $keyvalues ) {

    foreach my $block_name ( keys %{$blocks} ) {
        $blocks->{$block_name} =~ s{\[\%[ \t]*exim_?config\.(\S+)[ \t]*\%\]}{$keyvalues->{$1}}g;
    }

    return 1;
}

sub _setup_srs_config_file ( $self, $config_file = undef ) {

    $config_file //= $SRS_CONFIG_FILE;

    my $content = Cpanel::LoadFile::loadfile($config_file) // '';
    if ( $content =~ qr{^\s* \# \s* version \s* = \s* \Q${VERSION}\E \s*$}xmsi ) {
        $self->debug("Preserve existing srs configuration file");
        return;
    }

    # we have to adjust the srs_config when updating from a previous version of exim
    $self->warn("Regenerate srs configuration file");
    unlink($config_file);

    # Previous location for the srs secret storage
    my $SRS_SECRET = Cpanel::LoadFile::load_if_exists($SRS_SECRET_FILE);
    $SRS_SECRET //= Cpanel::Rand::Get::getranddata(32);

    Cpanel::SafeDir::MK::safemkdir( $HIDDEN_CONFIG_DIR, 0700 ) unless -d $HIDDEN_CONFIG_DIR;

    # SRS: secret only (cannot configure the days and hash lenght with native SRS)
    return Cpanel::FileUtils::Write::write( $config_file, <<~"EOS", 0600 );
        # version = ${VERSION}
        SRSENABLED = 1
        SRS_SECRET = ${SRS_SECRET}
        EOS
}

# In addition to the delimiter, carets must also be geminated, because Exim
# treats them specially in the client_send directive
sub _perform_client_send_escapes ($str) {
    $str =~ s/:/::/g;
    $str =~ s/\^/^^/g;
    return $str;
}

sub logger ($self) {
    return $self->{_logger} //= Cpanel::Logger->new();
}

sub warn ( $self, @args ) {
    return $self->logger->warn(@args);
}

sub info ( $self, @args ) {
    return $self->logger->info(@args);
}

sub debug ( $self, @args ) {
    return $self->logger->debug(@args);
}

1;
