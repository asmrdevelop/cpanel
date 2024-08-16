package Cpanel::Init::Simple;

# cpanel - Cpanel/Init/Simple.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

my $_init_obj;

=encoding utf-8

=head1 NAME

Cpanel::Init::Simple - A simple wrapper around Cpanel::Init intended to provide compatbility with /scripts/cpservice

=head1 SYNOPSIS

    use Cpanel::Init::Simple;

    Cpanel::Init::Simple::call_cpservice_with('mailman', 'install', 'enable');
    Cpanel::Init::Simple::call_cpservice_with('mailman', 'disable');

=head1 DESCRIPTION

This modules provides similar functionality to
calling /scripts/cpservice

=head2 call_cpservice_with($service, @actions)

Calls Cpanel::Init in the same was /scripts/cpservice does

=cut

sub call_cpservice_with {
    my ( $service, @actions ) = @_;

    foreach my $action (@actions) {

        _create_init_obj() if !$_init_obj;
        my $retval;
        if ( $action =~ m/\binstall\b|\buninstall\b|\benable\b|\bdisable\b|\badd\b|\bremove\b/i ) {
            local $@;
            $retval = eval { $_init_obj->run_command_for_one( $action, $service ); };
            if ( !$retval ) {
                if ($@) {
                    warn "Unable to run action “$action” for “$service”: $@";
                }
                else {
                    warn "Unable to run action “$action” for “$service”.";
                }
            }

        }
        else {
            local $@;
            $retval = eval { $_init_obj->run_command( $service, $action ); };
            if ($@) {
                warn;
            }
            elsif ( !$retval->{'status'} ) {
                warn $retval->{'message'};
            }
        }
    }

    return;
}

sub check_if_cpservice_exists {
    my ($service) = @_;

    _create_init_obj() if !$_init_obj;

    if ( !defined $_init_obj->get_script_for_service($service) ) {
        return 0;
    }
    else {
        return 1;
    }
}

sub _create_init_obj {
    require Cpanel::Init;
    $_init_obj ||= Cpanel::Init->new();
    return;
}

1;

__END__
