package Whostmgr::Config::Restore::System::ModSecurity;

# cpanel - Whostmgr/Config/Restore/System/ModSecurity.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Config::Restore::System::ModSecurity

=head1 DESCRIPTION

This module implements ModSecurity configuration restoration
for the transfer system.

This module subclasses L<Whostmgr::Config::Restore::Base>.

=cut

#----------------------------------------------------------------------

use parent qw( Whostmgr::Config::Restore::Base::JSON );

use Cpanel::CommandQueue ();

use Whostmgr::ModSecurity             ();
use Whostmgr::ModSecurity::Settings   ();
use Whostmgr::ModSecurity::VendorList ();
use Whostmgr::API::1::Utils::Execute  ();

#----------------------------------------------------------------------

sub _restore ( $self, $parent ) {

    local $self->{'_parent'} = $parent;

    # This die()s on a failure, so there should be no need to inspect
    # the return value. We just collect it to pass it on to the caller.
    my @ret = $self->SUPER::_restore($parent);

    return @ret;
}

sub _restore_from_structure ( $self, $conf ) {

    $self->{'__vendors'} = $conf->{'vendors'};

    # There’s no functional benefit to using C::CQ as this module stands
    # because there’s no rollback implemented. It’ll be useful, though,
    # to have the function divided up this way in the event we do implement
    # rollback, though.
    my $queue = Cpanel::CommandQueue->new();

    _enqueue_settings_changes( $conf, $queue );

    _enqueue_vendor_installs_uninstalls( $conf, $queue );

    $queue->add(
        sub {
            $self->_restore_modsec_files( $self->{'_parent'} );
        }
    );

    _enqueue_disabled_rules( $conf, $queue );

    _enqueue_disabled_configs( $conf, $queue );

    $queue->run();

    return;
}

sub _restore_modsec_files ( $self, $parent ) {

    my $vendors_ar = $self->{'__vendors'} or die 'Need vendors set in object!';

    my $vendor_dir = Whostmgr::ModSecurity::config_prefix() . '/' . Whostmgr::ModSecurity::vendor_configs_dir();

    for my $vendor_hr (@$vendors_ar) {
        my $id = $vendor_hr->{'vendor_id'};

        $parent->{'dirs_to_copy'}{"$vendor_dir/$id"} = { archive_dir => "cpanel/system/modsecurity/vendor_$id" };
    }

    return;
}

sub _enqueue_disabled_configs ( $conf, $queue ) {
    for my $vendor_hr ( @{ $conf->{'vendors'} } ) {
        for my $config_hr ( @{ $vendor_hr->{'configs'} } ) {
            next if $config_hr->{'active'};

            $queue->add(
                sub {
                    _execute_or_die(
                        'modsec_make_config_inactive',
                        { config => $config_hr->{'config'} },
                    );
                }
            );
        }
    }

    return;
}

sub _enqueue_disabled_rules ( $conf, $queue ) {
    my %vendor_rule_config;

    for my $rule_id ( keys %{ $conf->{'disabled_rules'} } ) {
        my $vendor_id = $conf->{'disabled_rules'}{$rule_id};

        $queue->add(
            sub {
                $vendor_rule_config{$vendor_id} ||= do {
                    my $result = _execute_or_die(
                        'modsec_get_rules',
                        { vendor_id => $vendor_id },
                    );

                    my $chunks = $result->get_data()->{'chunks'};

                    my %lookup = map { @{$_}{ 'id', 'config' } } @$chunks;

                    \%lookup;
                };

                my $config = $vendor_rule_config{$vendor_id}{$rule_id};

                # Since we’ll be dealing with the very .conf files that
                # were active in the backed-up configuration, all disabled
                # rules should actually exist. Still, we needn’t consider
                # a failure here to be fatal, so let’s trap errors here.

                local $@;
                warn if !eval {
                    _execute_or_die(
                        'modsec_disable_rule',
                        { config => $config, id => $rule_id },
                    );
                };
            },
        );
    }

    return;
}

sub _enqueue_vendor_installs_uninstalls ( $conf, $queue ) {
    my %archive_vendor_url = map { %{$_}{ 'vendor_id', 'installed_from' } } @{ $conf->{'vendors'} };

    my $installed_vendor_ids_ar = Whostmgr::ModSecurity::VendorList::list_vendor_ids();

    for my $vid (@$installed_vendor_ids_ar) {
        if ( !$archive_vendor_url{$vid} ) {
            $queue->add(
                sub { _execute_or_die( 'modsec_remove_vendor', { vendor_id => $vid } ) },
            );
        }
    }

    delete @archive_vendor_url{@$installed_vendor_ids_ar};

    for my $vendor_hr ( @{ $conf->{'vendors'} } ) {
        if ( !exists $archive_vendor_url{ $vendor_hr->{'vendor_id'} } ) {

            # The 'is_rpm' key is the old key and was added in version 92 via CPANEL-33703
            # The 'is_pkg' key deprecates the 'is_rpm' key.  This change was made in version 102
            # via CPANEL-39059
            # We need to account for both keys here since the target server may not yet have this change
            if ( defined $vendor_hr->{'is_pkg'} || defined $vendor_hr->{'is_rpm'} ) {
                my $pkg = $vendor_hr->{'is_pkg'};
                $pkg = $vendor_hr->{'is_rpm'} if defined $vendor_hr->{'is_rpm'};

                require Cpanel::SysPkgs;
                my $syspkgs = Cpanel::SysPkgs->new;
                $syspkgs->install( packages => [$pkg] );

                if ( $vendor_hr->{'enabled'} == 0 ) {
                    $queue->add(
                        sub {
                            _execute_or_die(
                                'modsec_disable_vendor',
                                {
                                    vendor_id => $vendor_hr->{'vendor_id'},
                                }
                            );
                        },
                    );
                }
            }
            else {
                $queue->add(
                    sub {
                        _execute_or_die(
                            'modsec_add_vendor',
                            {
                                url     => $vendor_hr->{'installed_from'},
                                enabled => $vendor_hr->{'enabled'},
                            }
                        );
                    },
                );
            }

            next if $vendor_hr->{'update'};
        }

        # It would be ideal to detect the current update status and forgo
        # the API call if the current status matches the archive. But this
        # works, too.

        my $update_fn = $vendor_hr->{'update'} ? 'modsec_enable_vendor_updates' : 'modsec_disable_vendor_updates';

        if ( !$vendor_hr->{'update'} ) {
            $queue->add(
                sub {
                    _execute_or_die(
                        $update_fn,
                        {
                            vendor_id => $vendor_hr->{'vendor_id'},
                        }
                    );
                },
            );
        }
    }

    return;
}

sub _enqueue_settings_changes ( $conf, $queue ) {
    my %new_settings = map { @{$_}{ 'setting_id', 'state' } } @{ $conf->{'settings'} };

    my %batch;

    my $current_ar = Whostmgr::ModSecurity::Settings::get_settings();

    for my $setting_hr (@$current_ar) {
        my $sid      = $setting_hr->{'setting_id'};
        my $batchnum = keys %batch;

        if ( exists $new_settings{$sid} ) {
            $batch{"state$batchnum"} = $new_settings{$sid};
        }
        elsif ( !$setting_hr->{'missing'} ) {
            $batch{"remove$batchnum"} = 1;
        }
        else {
            next;
        }

        $batch{"setting_id$batchnum"} = $sid;
    }

    if (%batch) {
        $batch{'commit'} = 1;

        $queue->add(
            sub {
                _execute_or_die( 'modsec_batch_settings', \%batch );
            }
        );
    }

    return;
}

sub _execute_or_die ( $fn, $args_hr ) {

    return Whostmgr::API::1::Utils::Execute::execute_or_die(
        'ModSecurity', $fn,
        $args_hr,
    );
}

1;
