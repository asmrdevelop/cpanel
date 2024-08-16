package Cpanel::Security::Advisor::Assessors::Imunify360;

# cpanel - Cpanel/Security/Advisor/Assessors/Imunify360.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use base 'Cpanel::Security::Advisor::Assessors';

use Cpanel::LoadModule ();
use Cpanel::Template   ();

use Cpanel::Imports;

sub version {
    return '2.00';
}

sub generate_advice {
    my ($self) = @_;

    eval {

        # These checks will only run on v80 and higher
        if ( _can_load_module('Whostmgr::Imunify360') && Whostmgr::Imunify360->new->should_offer() ) {    # PPI NO PARSE - dynamically loaded by _can_load_module

            $self->{i360} = {
                data      => Whostmgr::Imunify360::get_imunify360_data(),        # PPI NO PARSE - dynamically loaded by _can_load_module
                installed => Whostmgr::Imunify360::is_imunify360_installed(),    # PPI NO PARSE - dynamically loaded by _can_load_module
                licensed  => Whostmgr::Imunify360::is_imunify360_licensed(),     # PPI NO PARSE - dynamically loaded by _can_load_module
                price     => Whostmgr::Imunify360::get_imunify360_price(),       # PPI NO PARSE - dynamically loaded by _can_load_module
            };

            if ( !$self->{i360}{data}{disabled} ) {
                $self->_suggest_imunify360;
            }

        }

        # These checks will only run on v88 and higher.
        if ( !( $self->{i360} && $self->{i360}{installed} ) ) {

            if ( _can_load_module('Whostmgr::Store::Product::ImunifyAVPlus') ) {

                my $iavp_store = Whostmgr::Store::Product::ImunifyAVPlus->new( redirect_path => 'cgi/securityadvisor/index.cgi' );    # PPI NO PARSE - dynamically loaded by _can_load_module

                if ( $iavp_store->should_offer() ) {

                    $self->{iavp} = {
                        installed => $iavp_store->is_product_installed(),
                        licensed  => $iavp_store->is_product_licensed(),
                        price     => $iavp_store->get_product_price(),
                    };

                    my $iavp_url = $iavp_store->get_custom_url();
                    $self->{iavp}{url} = $iavp_url ? $iavp_url : $self->base_path('scripts14/purchase_imunifyavplus_init_SECURITYADVISOR');

                    $self->_suggest_iavp;

                }
            }

            if ( _can_load_module('Whostmgr::Store::Product::ImunifyAV') ) {
                my $iav_store = Whostmgr::Store::Product::ImunifyAV->new( redirect_path => 'cgi/securityadvisor/index.cgi' );    # PPI NO PARSE - dynamically loaded by _can_load_module
                if ( $iav_store->should_offer() ) {
                    $self->{iav}{installed} = $iav_store->is_product_installed();
                    $self->_suggest_iav;
                }
            }
        }
    };
    if ( my $exception = $@ ) {
        print STDERR $exception;    # STDERR gets sent to ULC/logs/error_log.

        if ( $exception =~ m{Unable to find the rpm binary} ) {
            return $self->add_bad_advice(
                key          => 'Immunify360_rpm_failure',
                text         => "Unable to determine if Imunify360 is installed",
                suggestion   => "Ensure that yum and rpm are working on your system.",
                block_notify => 1,                                                       # Do not send a notification>
            );
        }

        die $exception;
    }

    return 1;
}

sub _get_imunify_landing_page {
    my ($self) = @_;
    return $self->base_path('cgi/imunify/handlers/index.cgi');
}

sub _get_purchase_and_install_template {
    return << 'TEMPLATE';
[%- locale.maketext('Use [asis,Imunify360] for a comprehensive suite of protection against attacks on your servers.') %]
    <ul>
        <li>[%- locale.maketext('Multi-layered defense stops attacks with advanced firewall, herd immunity, Intrusion Prevention System, and more.') -%]</li>
        <li>[%- locale.maketext('Powered by AI with advanced detection of brute force attacks, zero-day, and unknown security threats.')-%]</li>
        <li>[%- locale.maketext('[asis,Proactive Defense™] recognizes malicious code in real-time and stops malware in its tracks.') -%]</li>
        <li>[%- locale.maketext('Easy management right inside your [asis,WHM] interface.')-%]</li>
        <li>[%- locale.maketext('Patch Management via [asis,KernelCare] and hardened [asis,PHP]')-%]</li>
        <li><a href="https://go.cpanel.net/buyimunify360" target="_new">[%- locale.maketext('Learn more about [asis,Imunify360]')%]</a></li>
    </ul>
[%- data.link -%]
TEMPLATE
}

sub _get_purchase_template {
    return << 'TEMPLATE';
<style>
#Imunify360_update_license blockquote {
    margin:0
}
</style>
<ul>
    <li>
    [%- data.link -%]
    </li>
    <li>
    [%- locale.maketext(
        'To uninstall [asis,Imunify360], read the [output,url,_1,Imunify360 Documentation,_2,_3].',
        'https://go.cpanel.net/imunify360uninstall',
        'target',
        '_blank',
    ) -%]
    </li>
</ul>
TEMPLATE
}

sub _get_install_template {
    return << 'TEMPLATE';
[%- locale.maketext(
        '[output,url,_1,Install Imunify360,_2,_3].',
        data.path,
        'target',
        '_parent'
) -%]
TEMPLATE
}

sub _process_template {
    my ( $template_ref, $args )   = @_;
    my ( $ok,           $output ) = Cpanel::Template::process_template(
        'whostmgr',
        {
            'template_file' => $template_ref,
            'data'          => $args,
        }
    );
    return $output if $ok;
    die "Template processing failed: $output";
}

sub _get_script_number() {
    return 'scripts14';
}

sub create_purchase_link {
    my ($self) = @_;

    my $installed = $self->{i360}{installed};
    my $price     = $self->{i360}{price};

    my $imunify360 = Whostmgr::Imunify360->new;       # PPI NO PARSE - dynamically loaded by _can_load_module
    my $custom_url = $imunify360->get_custom_url();

    my $cp_url = $self->base_path( _get_script_number() . '/purchase_imunify360_init' );

    if ($custom_url) {
        return locale()->maketext( '[output,url,_1,Get Imunify360,_2,_3].', $custom_url, 'target', '_blank', );
    }
    if ($installed) {
        return locale()->maketext( 'To purchase a license, visit the [output,url,_1,cPanel Store,_2,_3].', $cp_url, 'target', '_parent', );
    }
    if ($price) {
        return locale()->maketext( '[output,url,_1,Get Imunify360,_2,_3] for $[_4]/month.', $cp_url, 'target', '_parent', $price );
    }
    return locale()->maketext( '[output,url,_1,Get Imunify360,_2,_3].', $cp_url, 'target', '_parent', );
}

sub _suggest_imunify360 {
    my ($self) = @_;

    my $is_kernelcare_needed = Whostmgr::Imunify360->new()->needs_kernelcare();    # PPI NO PARSE - dynamically loaded by _can_load_module
    my $link                 = $self->create_purchase_link();

    if ( !$self->{i360}{installed} ) {

        my $output = _process_template(
            \_get_purchase_and_install_template(),
            {
                'link'               => $link,
                'include_kernelcare' => $is_kernelcare_needed,
            },
        );

        $self->add_info_advice(
            key          => 'Imunify360_purchase',
            text         => locale()->maketext('Use [asis,Imunify360] for complete protection against attacks on your servers.'),
            suggestion   => $$output,
            block_notify => 1,                                                                                                      # Do not send a notification about this
        );
    }
    elsif ( !Whostmgr::Imunify360->new()->is_running() ) {                                                                          # PPI NO PARSE - dynamically loaded by _can_load_module
        $self->add_bad_advice(
            key        => 'Imunify360_installed_not_running',
            text       => locale()->maketext('[asis,Imunify360] is installed but not running.'),
            suggestion => locale()->maketext('Start [asis,Imunify360] to ensure that your server is protected.'),
        );
    }
    else {

        $self->add_good_advice(
            key          => 'Imunify360_present',
            text         => locale()->maketext(q{Your server is protected by [asis,Imunify360].}),
            block_notify => 1,                                                                       # Do not send a notification about this
            infolink     => {
                text => locale()->maketext('For help getting started, read the [asis,Imunify360] documentation'),
                link => 'https://go.cpanel.net/imunify360gettingstarted',
            },
            landingpage => {
                text => locale()->maketext('Open Imunify360.'),
                link => $self->_get_imunify_landing_page(),
            },
        );
    }

    return 1;
}

sub _suggest_iav {
    my ($self) = @_;

    if ( !$self->{iavp}{licensed} ) {
        if ( $self->{iav}{installed} ) {
            $self->add_good_advice(
                key          => 'ImunifyAV_present',
                text         => locale()->maketext(q{Your server is protected by [asis,ImunifyAV].}),
                block_notify => 1,
                infolink     => {
                    text => locale()->maketext('For help getting started, read the [asis,ImunifyAV] documentation.'),
                    link => 'https://docs.imunifyav.com/imunifyav/'
                },
                landingpage => {
                    text => locale()->maketext('Go to [asis,ImunifyAV].'),
                    link => $self->_get_imunify_landing_page(),
                },
            );
        }
        else {
            $self->_avplus_advice( action => 'installav', advice => 'bad' );
        }

    }

    if ( $self->{iav}{installed} ) {
        my $rpm = _can_load_module('Cpanel::Binaries::Rpm')
          ? Cpanel::Binaries::Rpm->new()                            # PPI NO PARSE - dynamically loaded by _can_load_module - 98+
          : _can_load_module('Cpanel::RPM') ? Cpanel::RPM->new()    # PPI NO PARSE - dynamically loaded by _can_load_module - 96 and below
          :                                   undef;

        if ( $rpm && $rpm->has_rpm('cpanel-clamav') ) {

            my $plugins_url = $self->base_path('scripts2/manage_plugins');
            $self->add_info_advice(
                'key'          => 'ImunifyAV+_clam_and_iav_installed',
                'block_notify' => 1,
                'text'         => locale()->maketext("You have both ClamAV and ImunifyAV installed."),
                'suggestion'   => locale()->maketext( "ImunifyAV and ClamAV both provide antivirus coverage. To conserve resources you may want to [output,url,_1,Uninstall ClamAV,_2,_3]. However, ClamAV allows the “Scan outgoing messages for malware” setting to function. If you use this setting, keep ClamAV installed.", $plugins_url, 'target', '_blank' ),
            );
        }
    }

    return 1;
}

sub _suggest_iavp {
    my ($self) = @_;

    if ( !$self->{iavp}{licensed} ) {
        $self->_avplus_advice( action => 'upgrade', advice => 'info' );
    }
    elsif ( !$self->{iavp}{installed} && $self->{iavp}{licensed} ) {
        $self->_avplus_advice( action => 'installplus', advice => 'bad' );
    }
    elsif ( $self->{iavp}{installed} && $self->{iavp}{licensed} ) {
        my $landingpage_url = $self->base_path('cgi/imunify/handlers/index.cgi');

        $self->add_good_advice(
            key          => 'ImunifyAV+_present',
            text         => locale()->maketext(q{Your server is protected by [asis,ImunifyAV+].}),
            block_notify => 1,
            infolink     => {
                text => locale()->maketext('For help getting started, read the [asis,ImunifyAV+] documentation.'),
                link => 'https://docs.imunifyav.com/imunifyav/'
            },
            landingpage => {
                text => locale()->maketext('Go to [asis,ImunifyAV+].'),
                link => $self->_get_imunify_landing_page(),
            },
        );
    }

    return 1;
}

sub _upgrade_avplus_text {
    my ($self) = @_;
    return {
        text       => locale()->maketext("Use [asis,ImunifyAV+] to scan for malware and clean up infected files with one click."),
        link       => locale()->maketext( "[output,url,_1,Get ImunifyAV+,_2,_3] for \$[_4]/month.", $self->{iavp}{url}, 'target', '_blank', $self->{iavp}{price} ),
        suggestion => locale()->maketext("ImunifyAV+ brings you the advanced scanning of ImunifyAV and adds more options to make protecting servers from malicious code almost effortless. Enhanced features include:") . "<ul>" . "<li>"
          . locale()->maketext("Malware and virus scanning") . "</li>" . "<li>"
          . locale()->maketext("Automatic clean up") . "</li>" . "<li>"
          . locale()->maketext( "[output,url,_1,Learn more about ImunifyAV+,_2,_3]", 'https://go.cpanel.net/buyimunifyAVplus', 'target', '_blank' ) . "</li>" . "</ul>",
    };
}

sub _install_av_text {
    my ($self) = @_;
    my $install_av_url = $self->base_path('scripts14/install_imunifyav_SECURITYADVISOR');
    return {
        text       => locale()->maketext("Install [asis,ImunifyAV] to scan your websites for malware."),
        link       => locale()->maketext( "[output,url,_1,Install ImunifyAV,_2,_3] for free.", $install_av_url, 'target', '_blank' ),
        suggestion => '',
    };
}

sub _install_avplus_text {
    my ($self) = @_;
    my $install_plus_url = $self->base_path('scripts14/install_imunifyavplus_SECURITYADVISOR');
    return {
        text       => locale()->maketext("You have an [asis,ImunifyAV+] license, but you do not have [asis,ImunifyAV+] installed on your server."),
        link       => locale()->maketext( "[output,url,_1,Install ImunifyAV+,_2,_3].", $install_plus_url, 'target', '_blank' ),
        suggestion => '',
    };
}

sub _avplus_advice {
    my ( $self, %args ) = @_;

    my $content = {};

    if ( $args{action} eq 'upgrade' ) {
        $content = $self->_upgrade_avplus_text();
    }
    elsif ( $args{action} eq 'installav' ) {
        $content = $self->_install_av_text();
    }
    elsif ( $args{action} eq 'installplus' ) {
        $content = $self->_install_avplus_text();
    }
    else {
        return 0;
    }

    my %advice = (
        'key'          => "ImunifyAV+_$args{advice}",
        'block_notify' => 1,
        'text'         => $content->{text},
        'suggestion'   => $content->{suggestion} . $content->{link},
    );

    my $method = "add_$args{advice}_advice";
    return $self->$method(%advice);
}

sub _can_load_module {
    my ($mod) = @_;
    return eval { Cpanel::LoadModule::load_perl_module($mod) };
}

1;
