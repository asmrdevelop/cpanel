
# cpanel - Whostmgr/TweakSettings/Mail.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::TweakSettings::Mail;

use strict;
use warnings;

use Cpanel::Binaries                         ();
use Cpanel::Email::Config::SuspendedDelivery ();
use Cpanel::Logger                           ();
use Cpanel::Validate::IP                     ();
use Cpanel::StringFunc::Trim                 ();
use Cpanel::SafeDir::MK                      ();
use Cpanel::ServerTasks                      ();
use Cpanel::SSL::Defaults                    ();
use Cpanel::FileUtils::TouchFile             ();
use Cpanel::SMTP::ReverseDNSHELO             ();

my $logger;
my $security_token = $ENV{'cp_security_token'} || q{};

our %Conf_Opts = (
    'file'    => '/etc/exim.conf.localopts',
    'MailDir' => '/usr/local/cpanel/Whostmgr/TweakSettings/Mail',
);

our %Conf = (
    'manage_rbls_button' => {
        'type'   => 'button',
        'action' => "$security_token/cgi/addrbl.cgi",
        'target' => '_blank',
    },
    'sender_verify_bypass_ips_button' => {
        'type'   => 'button',
        'popup'  => 1,
        'action' => "$security_token/scripts2/iplisteditor?list=senderverifybypasshosts",
        'target' => '_blank',
    },

    'skip_smtp_check_ips_button' => {
        'type'   => 'button',
        'popup'  => 1,
        'action' => "$security_token/scripts2/iplisteditor?list=skipsmtpcheckhosts",
        'target' => '_blank',
    },
    'backup_mail_hosts_button' => {
        'type'   => 'button',
        'popup'  => 1,
        'action' => "$security_token/scripts2/iplisteditor?list=backupmxhosts",
        'target' => '_blank',
    },
    'trusted_mail_users_button' => {
        'type'   => 'button',
        'popup'  => 1,
        'action' => "$security_token/scripts2/iplisteditor?list=trustedmailusers",
        'target' => '_blank',
    },

    # This one is, by design, not a popup.
    'blocked_domains_button' => {
        'type'   => 'button',
        'action' => "$security_token/scripts12/mail_blocked_domains",
        'target' => '_blank',
    },

    'acl_mailproviders' => {
        'default' => 1,
        'type'    => 'binary',
    },
    'acl_trustedmailhosts' => {
        'default' => 0,
        'type'    => 'binary',
    },
    'acl_outgoing_malware_scan' => {
        'default' => 0,
        'type'    => 'binary',
        'skipif'  => sub {
            return if -x Cpanel::Binaries::path("clamd");
            return 1;
        },
    },
    'acl_outgoing_spam_scan' => {
        needs_role => 'SpamFilter',
        'default'  => 0,
        'excludes' => ['acl_outgoing_spam_scan_over_int'],
        'type'     => 'binary',
        'action'   => sub {
            my $val = shift;
            if ($val) {
                Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/outgoing_spam_scan');
            }
            else {
                unlink('/var/cpanel/outgoing_spam_scan');
            }
            return 1;
        },
    },
    'acl_outgoing_spam_scan_over_int' => {
        needs_role  => 'SpamFilter',
        'default'   => undef,
        'excludes'  => ['acl_outgoing_spam_scan'],
        'can_undef' => 1,
        'type'      => 'number',
        'minimum'   => 1,                            # minimum is 0.1 in UI (1 on disk)
        'maximum'   => 999,                          # maximum is 99.9 in UI (999 on disk)
        'checkval'  => \&_is_spam_score,
        'format'    => \&_format_spam_score,
        'action'    => sub {
            my $val = shift;
            if ($val) {
                Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/outgoing_spam_scan');
            }
            else {
                unlink('/var/cpanel/outgoing_spam_scan');
            }
            return 1;
        },

    },
    'no_forward_outbound_spam' => {
        needs_role => 'SpamFilter',
        'default'  => 0,
        'excludes' => ['no_forward_outbound_spam_over_int'],
        'type'     => 'binary',
    },
    'srs' => {
        'default' => 0,
        'type'    => 'binary',
    },
    'no_forward_outbound_spam_over_int' => {
        needs_role  => 'SpamFilter',
        'default'   => undef,
        'excludes'  => ['no_forward_outbound_spam'],
        'can_undef' => 1,
        'type'      => 'number',
        'minimum'   => 1,                              # minimum is 0.1 in UI (1 on disk)
        'maximum'   => 999,                            # maximum is 99.9 in UI (999 on disk)
        'checkval'  => \&_is_spam_score,
        'format'    => \&_format_spam_score,
    },
    'trusted_mail_hosts_ips_button' => {
        'type'   => 'button',
        'popup'  => 1,
        'action' => "$security_token/scripts2/iplisteditor?list=mostlytrustedmailhosts",
    },
    'spammer_list_ips_button' => {
        needs_role => 'SpamFilter',
        'type'     => 'button',
        'popup'    => 1,
        'action'   => "$security_token/scripts2/iplisteditor?list=spammeripblocks",
    },
    'acl_spamcop_rbl' => {
        needs_role => 'SpamFilter',
        'default'  => 0,
        'type'     => 'binary',
    },
    'acl_spamhaus_rbl' => {
        needs_role => 'SpamFilter',
        'default'  => 0,
        'type'     => 'binary',
    },
    'rbl_whitelist' => {
        'default'  => '',
        'type'     => 'textarea',
        'format'   => sub { return shift =~ s{[^0-9a-f:./]+}{\n}gr; },
        'width'    => 15,
        'checkval' => sub {
            my @split_input = split /[,;\s]+/, Cpanel::StringFunc::Trim::ws_trim( shift() );

            #no items that aren't valid IPs
            my $valid = !grep { !Cpanel::Validate::IP::is_valid_ip_cidr_or_prefix($_) } @split_input;

            return $valid
              ? join( ',', @split_input )
              : ();
        },
    },
    'rbl_whitelist_neighbor_netblocks' => {
        'default' => 1,
        'type'    => 'binary',
    },
    'rbl_whitelist_greylist_common_mail_providers' => {
        'default' => 1,
        'type'    => 'binary',
    },
    'rbl_whitelist_greylist_trusted_netblocks' => {
        'default' => 0,
        'type'    => 'binary',
    },
    'rewrite_from' => {
        'type'    => 'radio',
        'options' => [qw( remote all disable )],
        'default' => 'disable',
    },
    'spf_include_hosts' => {
        'default_text' => 'None',
        'default'      => '',
        'type'         => 'text',
        'checkval'     => sub {
            my ($hosts_string) = @_;
            require Cpanel::Validate::DNS::Tiny;
            my @hosts = split( m{[ \t]*[;,:]+[ \t]*}, $hosts_string );
            if ( grep { !Cpanel::Validate::DNS::Tiny::valid_dns_name($_) } @hosts ) {
                return ();
            }
            return $hosts_string;
        },
        'action' => sub {
            my ( $newval, $oldval, $force ) = @_;
            return 1 if !$force && ( $newval // '' ) eq ( $oldval // '' );
            Cpanel::ServerTasks::schedule_task( ['SPFTasks'], 5, 'update_all_users_spf_records' );
            return 1;
        },
    },

    'smarthost_routelist' => {
        'default'      => '',
        'default_text' => 'None',
        'type'         => 'text',
        'checkval'     => sub {
            require Whostmgr::Exim;
            my $val = Cpanel::StringFunc::Trim::ws_trim(shift);
            return () if $val && $val !~ /\s/;
            my $res = Whostmgr::Exim::validate_routelist($val);
            if ( $res->{'status'} ) {
                return $val;
            }
            return ();
        },
        'action' => sub {
            my ( $newval, $oldval, $force ) = @_;
            return 1 if !$force && ( $newval // '' ) eq ( $oldval // '' );

            Cpanel::ServerTasks::schedule_task( ['SPFTasks'], 5, 'update_all_users_spf_records' );
            return 1;
        },

    },
    'smarthost_auth_required' => {
        'default'       => 0,
        'type'          => 'binary',
        'requires_test' => [ '$smarthost_routelist', '!=', '' ],
    },
    'smarthost_username' => {
        'type'          => 'text',
        'requires'      => 'smarthost_auth_required',
        'default_text'  => 'None',
        'default'       => '',
        'can_undef'     => 1,
        'requires_test' => [ '$smarthost_routelist', '!=', '' ],
        'checkval'      => \&_can_be_expressed_in_exim_list,
    },
    'smarthost_password' => {
        'type'          => 'password',
        'requires'      => 'smarthost_auth_required',
        'default_text'  => 'None',
        'default'       => '',
        'can_undef'     => 1,
        'requires_test' => [ '$smarthost_routelist', '!=', '' ],
        'checkval'      => \&_can_be_expressed_in_exim_list,
    },
    'smarthost_autodiscover_spf_include' => {
        'default'  => 1,
        'type'     => 'binary',
        'requires' => 'smarthost_routelist',
        'action'   => sub {
            my ( $newval, $oldval, $force ) = @_;
            return 1 if !$force && ( $newval // '' ) eq ( $oldval // '' );

            Cpanel::ServerTasks::schedule_task( ['SPFTasks'], 5, 'update_all_users_spf_records' );
            return 1;
        },

    },
    'hosts_avoid_pipelining' => {
        'type'    => 'binary',
        'default' => 0,
    },
    'suspended_account_deliveries' => {
        'type'    => 'radio',
        'options' => [
            Cpanel::Email::Config::SuspendedDelivery::DELIVER(),
            Cpanel::Email::Config::SuspendedDelivery::DISCARD(),

            # Cpanel::Email::Config::SuspendedDelivery::BOUNCE(),
            Cpanel::Email::Config::SuspendedDelivery::BLOCK(),
            Cpanel::Email::Config::SuspendedDelivery::QUEUE()
        ],
        'optionlabels' => \%Cpanel::Email::Config::SuspendedDelivery::SUSPENDED_LABEL_MAPPING,
        'default'      => Cpanel::Email::Config::SuspendedDelivery::recommended_setting(),
        'value'        => sub {
            return Cpanel::Email::Config::SuspendedDelivery::current_setting();
        },
        'action' => sub {
            my ( $newval, $oldval, $force ) = @_;
            return 1 if ( !$force && ( $newval // '' ) eq ( $oldval // '' ) && -e Cpanel::Email::Config::SuspendedDelivery::suspended_list_path() );
            return Cpanel::Email::Config::SuspendedDelivery::set_value($newval);
        },
    },
    'acl_dictionary_attack' => {
        'default' => 1,
        'type'    => 'binary',
    },

    'acl_requirehelo' => {
        'default' => 1,
        'type'    => 'binary',
    },

    'acl_requirehelosyntax' => {
        'default'  => 1,
        'type'     => 'binary',
        'requires' => 'acl_requirehelo',
    },
    'acl_requirehelonoforge' => {
        'default'  => 1,
        'type'     => 'binary',
        'requires' => 'acl_requirehelo',
    },
    'acl_delay_unknown_hosts' => {
        'default' => 1,
        'type'    => 'binary',
    },
    'acl_dont_delay_greylisting_trusted_hosts' => {
        'default'  => 1,
        'type'     => 'binary',
        'requires' => 'acl_delay_unknown_hosts',
    },
    'acl_dont_delay_greylisting_common_mail_providers' => {
        'default'  => 0,
        'type'     => 'binary',
        'requires' => 'acl_delay_unknown_hosts',
    },
    'acl_requirehelonold' => {
        'default'  => 0,
        'type'     => 'binary',
        'requires' => 'acl_requirehelo',
    },
    'acl_slow_fail_block' => {
        'default' => 1,
        'type'    => 'binary',
    },
    'acl_spam_scan_secondarymx' => {
        needs_role => 'SpamFilter',
        'default'  => 1,
        'type'     => 'binary',
    },
    'acl_ratelimit' => {
        'default' => 1,
        'type'    => 'binary',
    },
    'acl_dkim_bl' => {
        'default'  => 0,
        'type'     => 'binary',
        'excludes' => 'acl_dkim_disable',
    },
    'acl_dkim_disable' => {
        'default' => 1,
        'type'    => 'inversebinary',
    },
    'acl_primary_hostname_bl' => {
        'default' => 0,
        'type'    => 'binary',
    },
    'acl_deny_spam_score_over_int' => {
        needs_role  => 'SpamFilter',
        'default'   => undef,
        'width'     => 5,
        'can_undef' => 1,
        'type'      => 'text',
        'checkval'  => \&_is_spam_score,
        'format'    => \&_format_spam_score,
    },
    'acl_ratelimit_spam_score_over_int' => {
        needs_role  => 'SpamFilter',
        'default'   => undef,
        'width'     => 5,
        'can_undef' => 1,
        'type'      => 'text',
        'checkval'  => \&_is_spam_score,
        'format'    => \&_format_spam_score,
    },
    'filter_attachments' => {
        'default'       => 1,
        'type'          => 'binary',
        'requires_test' => [ '$systemfilter', '==', '/etc/cpanel_exim_system_filter' ]
    },
    'spam_header' => {
        needs_role => 'SpamFilter',
        'default'  => '***SPAM***',
        'type'     => 'text',
        'format'   => sub {
            my $value = shift();

            return $value eq q{}
              ? '***SPAM***'
              : $value;
        },
    },
    'filter_spam_rewrite' => {
        needs_role      => 'SpamFilter',
        'default'       => 1,
        'type'          => 'binary',
        'requires_test' => [ '$systemfilter', '==', '/etc/cpanel_exim_system_filter' ]
    },
    'filter_fail_spam_score_over_int' => {
        needs_role  => 'SpamFilter',
        'default'   => undef,
        'width'     => 5,
        'can_undef' => 1,
        'type'      => 'text',
        'checkval'  => \&_is_spam_score,
        'format'    => \&_format_spam_score,
    },
    'systemfilter' => {
        'default'    => '/etc/cpanel_exim_system_filter',
        'revertable' => 1,
        'type'       => 'path',
        'can_undef'  => 1,
        'checkval'   => sub {
            my $value = shift();

            return defined $value && ( $value eq '/etc/cpanel_exim_system_filter' || ( -f $value && -r $value ) )
              ? $value
              : ();
        }
    },
    'trust_x_php_script' => {
        'default' => 1,
        'type'    => 'binary',
        'value'   => sub { return -e '/var/cpanel/config/email/trust_x_php_script' ? 1 : 0; },
        'action'  => sub {
            my ($val) = @_;
            Cpanel::SafeDir::MK::safemkdir( '/var/cpanel/config/email', 0755 );
            if ($val) {
                Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/config/email/trust_x_php_script');
            }
            else {
                unlink('/var/cpanel/config/email/trust_x_php_script');
            }
            return 1;
        }
    },
    'query_apache_for_nobody_senders' => {
        'default' => 1,
        'type'    => 'binary',
        'value'   => sub { return -e '/var/cpanel/config/email/query_apache_for_nobody_senders' ? 1 : 0; },
        'action'  => sub {
            my ($val) = @_;
            Cpanel::SafeDir::MK::safemkdir( '/var/cpanel/config/email', 0755 );
            if ($val) {
                Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/config/email/query_apache_for_nobody_senders');
            }
            else {
                unlink('/var/cpanel/config/email/query_apache_for_nobody_senders');
            }
            return 1;
        }
    },

    'custom_mailips' => {
        'excludes' => 'per_domain_mailips',
        'default'  => 0,
        'type'     => 'binary',
        'value'    => sub { return -e '/var/cpanel/custom_mailips' ? 1 : 0; },
        'action'   => sub {
            my $val    = shift;
            my $oldval = shift;
            if ($val) {
                Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/custom_mailips');
            }
            else {
                unlink('/var/cpanel/custom_mailips');
            }
            if ( $val ne $oldval ) {
                _schedule_update_userdomains();
            }
            return 1;
        }
    },
    'spamassassin_plugin_P0f' => {
        needs_role => 'SpamFilter',
        'default'  => 1,
        'type'     => 'binary',
        'value'    => sub { return -e '/etc/mail/spamassassin/P0f.cf' ? 1 : 0; },
        'action'   => sub {
            my ($val) = @_;
            my $changed = 0;
            if ($val) {
                if ( !-e '/etc/mail/spamassassin/P0f.cf' ) {
                    _assure_etc_mail_spamassassin();
                    if ( symlink( '/usr/local/cpanel/etc/mail/spamassassin/P0f.cf', '/etc/mail/spamassassin/P0f.cf' ) ) {
                        $changed = 1;
                    }
                    else {
                        _logger()->warn("Failed to symlink /usr/local/cpanel/etc/mail/spamassassin/P0f.cf => /etc/mail/spamassassin/P0f.cf: $!");
                    }
                }
            }
            else {
                $changed = 1 if unlink('/etc/mail/spamassassin/P0f.cf');
            }

            # Schedule in a second.
            eval {
                Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 1, "restartsrv spamd" );
                1;
            } or do {
                print $@;
                return 0;
            };
            return 1;
        }
    },
    'spamassassin_plugin_KAM' => {
        needs_role => 'SpamFilter',
        'default'  => 1,
        'type'     => 'binary',
        'value'    => sub { return -e '/etc/mail/spamassassin/KAM.cf' ? 1 : 0; },
        'action'   => sub {
            my ($val) = @_;

            my $changed = 0;
            if ($val) {
                _assure_etc_mail_spamassassin();
                if ( !-e '/etc/mail/spamassassin/KAM.cf' ) {
                    if ( symlink( '/usr/local/cpanel/etc/mail/spamassassin/KAM.cf', '/etc/mail/spamassassin/KAM.cf' ) ) {
                        $changed = 1;
                    }
                    else {
                        _logger()->warn("Failed to symlink /usr/local/cpanel/etc/mail/spamassassin/KAM.cf => /etc/mail/spamassassin/KAM.cf: $!");
                    }
                }
                if ( !-e '/etc/mail/spamassassin/kam_heavyweights.cf' ) {
                    if ( symlink( '/usr/local/cpanel/etc/mail/spamassassin/kam_heavyweights.cf', '/etc/mail/spamassassin/kam_heavyweights.cf' ) ) {
                        $changed = 1;
                    }
                    else {
                        _logger()->warn("Failed to symlink /usr/local/cpanel/etc/mail/spamassassin/kam_heavyweights.cf => /etc/mail/spamassassin/kam_heavyweights.cf: $!");
                    }
                }
                if ( !-e '/etc/mail/spamassassin/deadweight.cf' ) {
                    if ( symlink( '/usr/local/cpanel/etc/mail/spamassassin/deadweight.cf', '/etc/mail/spamassassin/deadweight.cf' ) ) {
                        $changed = 1;
                    }
                    else {
                        _logger()->warn("Failed to symlink /usr/local/cpanel/etc/mail/spamassassin/deadweight.cf => /etc/mail/spamassassin/deadweight.cf: $!");
                    }
                }
                if ( !-e '/etc/mail/spamassassin/deadweight2.cf' ) {
                    if ( symlink( '/usr/local/cpanel/etc/mail/spamassassin/deadweight2.cf', '/etc/mail/spamassassin/deadweight2.cf' ) ) {
                        $changed = 1;
                    }
                    else {
                        _logger()->warn("Failed to symlink /usr/local/cpanel/etc/mail/spamassassin/deadweight2.cf => /etc/mail/spamassassin/deadweight2.cf: $!");
                    }
                }
                if ( !-e '/etc/mail/spamassassin/deadweight2_meta.cf' ) {
                    if ( symlink( '/usr/local/cpanel/etc/mail/spamassassin/deadweight2_meta.cf', '/etc/mail/spamassassin/deadweight2_meta.cf' ) ) {
                        $changed = 1;
                    }
                    else {
                        _logger()->warn("Failed to symlink /usr/local/cpanel/etc/mail/spamassassin/deadweight2_meta.cf => /etc/mail/spamassassin/deadweight2_meta.cf: $!");
                    }
                }
                if ( !-e '/etc/mail/spamassassin/deadweight2_sub.cf' ) {
                    if ( symlink( '/usr/local/cpanel/etc/mail/spamassassin/deadweight2_sub.cf', '/etc/mail/spamassassin/deadweight2_sub.cf' ) ) {
                        $changed = 1;
                    }
                    else {
                        _logger()->warn("Failed to symlink /usr/local/cpanel/etc/mail/spamassassin/deadweight2_sub.cf => /etc/mail/spamassassin/deadweight2_sub.cf: $!");
                    }
                }
            }
            else {
                # FIXME: If the first unlink() succeeds but subsequent unlink()s fail for transient reasons, some KAM rules will remain, even though WHM says it's off.
                $changed = 1 if ( unlink('/etc/mail/spamassassin/KAM.cf')
                    && unlink('/etc/mail/spamassassin/kam_heavyweights.cf')
                    && unlink('/etc/mail/spamassassin/deadweight.cf')
                    && unlink('/etc/mail/spamassassin/deadweight2.cf')
                    && unlink('/etc/mail/spamassassin/deadweight2_meta.cf')
                    && unlink('/etc/mail/spamassassin/deadweight2_sub.cf') );
            }

            # Schedule in a second.
            eval {
                Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 1, "restartsrv spamd" );
                1;
            } or do {
                print $@;
                return 0;
            };
            return 1;
        }
    },

    'spamassassin_plugin_BAYES_POISON_DEFENSE' => {
        needs_role => 'SpamFilter',
        'default'  => 1,
        'type'     => 'binary',
        'value'    => sub { return -e '/etc/mail/spamassassin/BAYES_POISON_DEFENSE.cf' ? 1 : 0; },
        'action'   => sub {
            my ($val) = @_;
            my $changed = 0;
            if ($val) {
                if ( !-e '/etc/mail/spamassassin/BAYES_POISON_DEFENSE.cf' ) {
                    _assure_etc_mail_spamassassin();
                    if ( symlink( '/usr/local/cpanel/etc/mail/spamassassin/BAYES_POISON_DEFENSE.cf', '/etc/mail/spamassassin/BAYES_POISON_DEFENSE.cf' ) ) {
                        $changed = 1;
                    }
                    else {
                        _logger()->warn("Failed to symlink /usr/local/cpanel/etc/mail/spamassassin/BAYES_POISON_DEFENSE.cf => /etc/mail/spamassassin/BAYES_POISON_DEFENSE.cf: $!");
                    }
                }
            }
            else {
                $changed = 1 if unlink('/etc/mail/spamassassin/BAYES_POISON_DEFENSE.cf');
            }

            # Schedule in a second.
            eval {
                Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 1, "restartsrv spamd" );
                1;
            } or do {
                print $@;
                return 0;
            };
            return 1;
        }
    },
    'spamassassin_plugin_CPANEL' => {
        needs_role => 'SpamFilter',
        'default'  => 1,
        'type'     => 'binary',
        'value'    => sub { return -e '/etc/mail/spamassassin/CPANEL.cf' ? 1 : 0; },
        'action'   => sub {
            my ($val) = @_;
            my $changed = 0;
            if ($val) {
                if ( !-e '/etc/mail/spamassassin/CPANEL.cf' ) {
                    _assure_etc_mail_spamassassin();
                    if ( symlink( '/usr/local/cpanel/etc/mail/spamassassin/CPANEL.cf', '/etc/mail/spamassassin/CPANEL.cf' ) ) {
                        $changed = 1;
                    }
                    else {
                        _logger()->warn("Failed to symlink /usr/local/cpanel/etc/mail/spamassassin/CPANEL.cf => /etc/mail/spamassassin/CPANEL.cf: $!");
                    }
                }
            }
            else {
                $changed = 1 if unlink('/etc/mail/spamassassin/CPANEL.cf');
            }

            # Schedule in a second.
            eval {
                Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 1, "restartsrv spamd" );
                1;
            } or do {
                print $@;
                return 0;
            };
            return 1;
        }
    },
    'custom_mailhelo' => {
        'excludes' => [ 'per_domain_mailips', 'use_rdns_for_helo' ],
        'default'  => 0,
        'type'     => 'binary',
        'value'    => sub { return -e '/var/cpanel/custom_mailhelo' ? 1 : 0; },
        'action'   => sub {
            my $val    = shift;
            my $oldval = shift;
            if ($val) {
                Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/custom_mailhelo');
            }
            else {
                unlink('/var/cpanel/custom_mailhelo');
            }
            if ( $val ne $oldval ) {
                _schedule_update_userdomains();
            }
            return 1;
        }
    },
    'per_domain_mailips' => {
        'default' => 0,
        'type'    => 'binary',
        'value'   => sub { return -e '/var/cpanel/per_domain_mailips' ? 1 : 0; },
        'action'  => sub {
            my $val    = shift;
            my $oldval = shift;

            if ($val) {
                Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/per_domain_mailips');
            }
            else {
                unlink('/var/cpanel/per_domain_mailips');
            }
            if ( $val ne $oldval ) {
                _schedule_update_userdomains();
            }
            return 1;
        }
    },

    'use_rdns_for_helo' => {
        'default' => 1,
        'type'    => 'binary',
        'value'   => sub { return Cpanel::SMTP::ReverseDNSHELO->is_on() },
        'action'  => sub {
            my $val    = shift;
            my $oldval = shift;

            if ($val) {
                Cpanel::SMTP::ReverseDNSHELO->set_on();
            }
            else {
                Cpanel::SMTP::ReverseDNSHELO->set_off();
            }
            if ( $val ne $oldval ) {
                _schedule_update_userdomains();
            }
            return 1;
        }
    },

    # Not a setting, just a button. FYI.
    'rebuild_rdns_cache' => {
        'default' => 0,
        'type'    => 'button',
        'action'  => "$security_token/scripts7/rebuild_rdns_cache/",
        'skipif'  => sub {
            return 0 if Cpanel::SMTP::ReverseDNSHELO->is_on();
            return 1;
        },
    },
    'globalspamassassin' => {
        needs_role => 'SpamFilter',
        'default'  => 0,
        'type'     => 'binary',
        'value'    => sub { return -e '/etc/global_spamassassin_enable' ? 1 : 0; },
        'action'   => sub {
            my $val = shift;
            if ($val) {
                Cpanel::FileUtils::TouchFile::touchfile('/etc/global_spamassassin_enable');
            }
            else {
                unlink('/etc/global_spamassassin_enable');
            }
            return 1;
        }
    },
    'max_spam_scan_size' => {
        needs_role => 'SpamFilter',
        'default'  => '1000',
        'width'    => 5,
        'type'     => 'text',
        'unit'     => 'KB',
        'checkval' => sub {
            my $val = shift();

            return $val =~ m{\A \d+ \z}x
              ? $val + 0
              : ();
        },
    },
    'exiscanall' => {
        'default' => 0,
        'type'    => 'binary',
        'skipif'  => sub {
            return if -x Cpanel::Binaries::path("clamd");
            return 1;
        },
    },
    'allowweakciphers' => {
        'default' => 0,
        'type'    => 'binary'
    },
    'spam_deferok' => {
        needs_role => 'SpamFilter',
        'default'  => 1,
        'type'     => 'binary'
    },
    'malware_deferok' => {
        'default' => 1,
        'type'    => 'binary'
    },
    'setsenderheader' => {
        'default' => 0,
        'type'    => 'binary'
    },
    'callouts' => {
        'default'  => 0,
        'type'     => 'binary',
        'requires' => 'senderverify'
    },
    'acl_0tracksenders' => {
        'default' => 0,
        'type'    => 'binary',
    },
    'senderverify' => {
        'default' => 1,
        'type'    => 'binary'
    },
    'acl_deny_rcpt_soft_limit' => {
        'default'   => undef,
        'width'     => 5,
        'can_undef' => 1,
        'type'      => 'number',
        'minimum'   => 1,
        'maximum'   => 100,
    },
    'acl_deny_rcpt_hard_limit' => {
        'default'   => undef,
        'width'     => 5,
        'can_undef' => 1,
        'type'      => 'number',
        'minimum'   => 1,
        'maximum'   => 100,
    },
    'require_secure_auth' => {
        'default' => 1,
        'type'    => 'binary',
    },
    'openssl_options' => {
        'default' => lc Cpanel::SSL::Defaults::default_protocol_list( { type => 'negative', delimiter => ' ', negation => '+no_', all => '', separator => '_' } ),
        'width'   => 32,
        'type'    => 'text',
    },
    'tls_require_ciphers' => {
        'default' => Cpanel::SSL::Defaults::default_cipher_list(),
        'width'   => 32,
        'type'    => 'text',
    },
    'dsn_advertise_hosts' => {
        'default'   => undef,
        'can_undef' => 1,
        'width'     => 32,
        'type'      => 'text',
    },
    'smtputf8_advertise_hosts' => {
        'default'   => undef,
        'can_undef' => 1,
        'width'     => 32,
        'type'      => 'text',
    },
    'filter_emails_by_country_button' => {
        'type'   => 'button',
        'action' => "$security_token/scripts12/mail_blocked_countries/",
        'target' => '_blank',
    },
    'message_linelength_limit' => {
        'default'   => 2048,
        'width'     => 5,
        'can_undef' => 0,
        'type'      => 'number',
        'minimum'   => 1,
        'maximum'   => 1000000,
    },
    'mailbox_quota_query_timeout' => {
        'default'  => '45s',
        'type'     => 'text',
        'width'    => 5,
        'checkval' => \&check_time_interval,
    },
);

sub get_conf {
    my %conf_copy = %Conf;

    require Cpanel::Server::Type::Profile::Roles;

    for my $key ( keys %conf_copy ) {
        if ( my $role_req = $conf_copy{$key}{'needs_role'} ) {
            if ( !Cpanel::Server::Type::Profile::Roles::are_roles_enabled($role_req) ) {
                delete $conf_copy{$key};
            }
        }
    }

    return wantarray ? %conf_copy : \%conf_copy;
}

sub check_time_interval {
    my ($interval) = @_;

    # Defined here https://www.exim.org/exim-html-current/doc/html/spec_html/ch-the_exim_runtime_configuration_file.html section 16 Time Intervals
    return $interval if length $interval && $interval =~ m/\A(?:[1-9][0-9]*w)?(?:[1-9][0-9]*d)?(?:[1-9][0-9]*h)?(?:[1-9][0-9]*m)?(?:[1-9][0-9]*s)?\z/;
    return;
}

sub get_message_linelength_limit_default {
    my %conf_copy = %Conf;
    return $conf_copy{'message_linelength_limit'}{'default'};
}

sub _assure_etc_mail_spamassassin {
    return 1 if -d '/etc/mail/spamassassin';
    require Cpanel::Umask;
    my $umask = Cpanel::Umask->new(022);
    unlink '/etc/mail/spamassassin', '/etc/mail';
    Cpanel::SafeDir::MK::safemkdir( '/etc/mail/spamassassin', 0755 );

    return 2;
}

sub get_conf_opts {
    my %conf_opts_copy = %Conf_Opts;
    return wantarray ? %conf_opts_copy : \%conf_opts_copy;
}

sub _is_spam_score {    #positive or negative, one decimal point
    my $val = shift();

    if ( defined $val && $val =~ m{\A \s* (-? \d+ (?:\.\d)?) \s* \z}xms ) {
        return $1 * 10;    #exim can't do floating point, so store as integers
    }
    else {
        return;
    }
}

sub _format_spam_score {
    my $val = shift;

    if ( defined $val ) {
        return $val / 10;
    }
    else {
        return;
    }
}

sub _can_be_expressed_in_exim_list {

    # Things Exim doesn't allow:
    # - leading or trailing whitespace (these are ignored in lists)
    # - leading caret ("^^^" could be "\0^" or "^\0", so it always chooses the latter)
    my $passwd = shift;
    return '' if $passwd eq '';
    return substr( $passwd, 0, 1 ) eq '^' || $passwd ne Cpanel::StringFunc::Trim::ws_trim($passwd)
      ? ( undef, "Due to limitations with Exim, this value cannot start or end with spaces or start with a caret character (^)" )
      : $passwd;
}

sub _schedule_update_userdomains {

    Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 5, "update_userdomains --force" );
    return;
}

#called from main TweakSettings::process_input_values
sub post_process {
    our %Conf;
    my ( $input_values_hr, $newvalues_hr ) = @_;

    foreach my $input_key ( keys %{$input_values_hr} ) {
        next if exists $Conf{$input_key};

        #add RBLs
        if ( $input_key =~ m{\Aacl_.*_rbl\z} ) {
            $newvalues_hr->{$input_key} = $input_values_hr->{$input_key};
        }
    }

    return;
}

sub _logger {
    $logger ||= Cpanel::Logger->new();
    return $logger;
}

1;

__END__
#'Grouping' => {
#        'key' => {
#                'checkval' => sub{return shift;}, # scrub/sanitize/validate
#                'default' => 30,              # Value when $FORM{'key'} eq ''
#                'help' => 'Text to display',  # Description
#                'name' => 'A Friendly Name',  # More friendly name
#                'type' => 'number'            # Form type
#                'action' => sub {             # return 1 for success 0 for failure
#                                   my $val = shift; # NEW value
#                                   my $oldval = shift; # OLD value
#                                   return 1 if ($val eq $oldval);
#                                   if ($val) { print "do stuff\n"; return 1;}
#                                   else { print "do other stuff\n"; return 1;}
#                },
#               'format' => sub { }  # How to present the data in the form
#        }
#},
