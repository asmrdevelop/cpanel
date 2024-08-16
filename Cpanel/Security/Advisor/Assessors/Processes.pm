package Cpanel::Security::Advisor::Assessors::Processes;

# cpanel - Cpanel/Security/Advisor/Assessors/Processes.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use base 'Cpanel::Security::Advisor::Assessors';

use Cpanel::OS ();

sub version {
    return '1.01';
}

sub generate_advice {
    my ($self) = @_;

    require Cpanel::Exception;
    require Cpanel::ProcessCheck::Outdated;
    $self->_check_for_outdated_processes;

    return 1;
}

sub _check_for_outdated_processes {
    my ($self) = @_;

    my $reboot = eval { Cpanel::ProcessCheck::Outdated::reboot_suggested() };
    if ( my $err = $@ ) {
        if ( ref $err && $err->isa('Cpanel::Exception::Service::BinaryNotFound') ) {
            $self->add_info_advice(
                key        => 'Processes_unable_to_check_running_executables',
                text       => $self->_lh->maketext('Unable to check whether running executables are up-to-date.'),
                suggestion => $self->_lh->maketext(
                    'Install the ‘[_1]’ command to check if processes are up-to-date.',
                    $err->get('service'),
                ),
            );
            return;    # Cannot check any other cases, so abort.
        }
        elsif ( !ref $err || !$err->isa('Cpanel::Exception::Unsupported') ) {
            $self->add_warn_advice(
                key  => 'Processes_error_while_checking_reboot',
                text => $self->_lh->maketext( 'Failed to determine if a reboot is necessary: [_1]', Cpanel::Exception::get_string_no_id($err) ),
            );
        }
    }

    if ($reboot) {
        $self->add_bad_advice(
            key        => 'Processes_detected_running_from_outdated_executables',
            text       => $self->_lh->maketext('The system’s core libraries or services have been updated.'),
            suggestion => $self->_lh->maketext(
                '[output,url,_1,Reboot the server,_2,_3] to ensure the system benefits from these updates.',
                $self->base_path('scripts/dialog?dialog=reboot'),
                'target',
                '_blank',
            ),
        );
        return;    # No need to check further.
    }

    my @services = eval { Cpanel::ProcessCheck::Outdated::outdated_services() };
    if ( my $err = $@ ) {
        if ( !ref $err || !$err->isa('Cpanel::Exception::Unsupported') ) {
            $self->add_warn_advice(
                key  => 'Processes_error_while_checking_running_services',
                text => $self->_lh->maketext( 'Failed to check whether active services are up-to-date: [_1]', Cpanel::Exception::get_string_no_id($err) ),
            );
        }
    }

    if (@services) {
        my $restart_cmd = 'systemctl restart ' . join( q{ }, @services );
        my $systemd     = Cpanel::OS::is_systemd();

        if ( !$systemd ) {
            $restart_cmd = 'service';
            @services    = map { s/\.service$//r } @services;
        }

        $self->add_bad_advice(
            key  => 'Processes_detected_running_outdated_services',
            text => $self->_lh->maketext(
                'Detected [quant,_1,service,services] that [numerate,_1,is,are] running outdated executables: [join, ,_2]',
                scalar @services,
                \@services,
            ),
            suggestion => _make_unordered_list(
                $self->_lh->maketext('You must take one of the following actions to ensure the system is up-to-date:'),
                $self->_lh->maketext(
                    'Restart the listed [numerate,_1,service,services] using “[_2]”; then click “[_3]” to check non-service processes.',
                    scalar @services,
                    $restart_cmd,
                    'Scan Again',    # Not translated in pkg/templates/main.tmpl
                ),
                $self->_lh->maketext(
                    '[output,url,_1,Reboot the server,_2,_3].',
                    $self->base_path('scripts/dialog?dialog=reboot'),
                    'target',
                    '_blank',
                ),
            ),
        );
        return;    # No need to check further.
    }

    my @PIDs = eval { Cpanel::ProcessCheck::Outdated::outdated_processes() };
    if ( my $err = $@ ) {
        if ( !ref $err || !$err->isa('Cpanel::Exception::Unsupported') ) {
            $self->add_warn_advice(
                key  => 'Processes_error_while_checking_running_executables',
                text => $self->_lh->maketext( 'Failed to check whether running executables are up-to-date: [_1]', Cpanel::Exception::get_string_no_id($err) ),
            );
        }
        return;    # We can't check anything, so don't report anything.
    }

    if (@PIDs) {
        my $suggestion;
        if ( grep { $_ eq '1' } @PIDs ) {    # If initd or systemd needs update, just suggest reboot.
            $suggestion = $self->_lh->maketext(
                '[output,url,_1,Reboot the server,_2,_3] to ensure the system benefits from these updates.',
                $self->base_path('scripts/dialog?dialog=reboot'),
                'target',
                '_blank',
            );
        }
        else {
            $suggestion = _make_unordered_list(
                $self->_lh->maketext('You must take one of the following actions to ensure the system is up-to-date:'),
                $self->_lh->maketext(
                    'Restart the listed [numerate,_1,process,processes].',
                    scalar @PIDs,
                ),
                $self->_lh->maketext(
                    '[output,url,_1,Reboot the server,_2,_3].',
                    $self->base_path('scripts/dialog?dialog=reboot'),
                    'target',
                    '_blank',
                )
            );
        }

        $self->add_bad_advice(
            key  => 'Processes_detected_running_outdated_executables',
            text => $self->_lh->maketext(
                'Detected [quant,_1,process,processes] that [numerate,_1,is,are] running outdated executables: [join, ,_2]',
                scalar @PIDs,
                \@PIDs,
            ),
            suggestion => $suggestion,
        );
        return;    # Error reported.
    }

    $self->add_good_advice(
        key  => 'Processes_none_with_outdated_executables',
        text => $self->_lh->maketext('The system did not detect processes with outdated binaries.')
    );

    return 1;
}

# Do this to work around bad perltidy concatenation rules.
sub _make_unordered_list {
    my ( $title, @items ) = @_;

    my $output = $title;
    $output .= '<ul>';
    foreach my $item (@items) {
        $output .= "<li>$item</li>";
    }
    $output .= '</ul>';

    return $output;
}

1;
