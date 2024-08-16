package Cpanel::Security::AdvisorFetch;

# cpanel - Cpanel/Security/AdvisorFetch.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Security::AdvisorFetch

=head1 SYNOPSIS

    my $msgs_ar = Cpanel::Security::AdvisorFetch::fetch_security_advice();

=head1 DESCRIPTION

This queries L<Cpanel::Security::Advisor> for messages and returns the
result. It filters and transforms the messages, thus:

=over

=item * C<mod_load> and C<mod_run> messages that aren’t failure notifications
are omitted from the response. For the failure messages, only C<type>,
C<module>, and C<message> attributes are returned.

=item * C<mod_advice> messages contain only C<type>, C<module>, and C<advice>.
Any such message that doesn’t include C<advice> is omitted.

=item * Other message types are omitted.

=item * Links in C<text> and C<suggestion> advice components are converted to
absolute URLs.

=back

=cut

#----------------------------------------------------------------------

use Capture::Tiny                ();
use Cpanel::Security::Advisor    ();    ## PPI NO PARSE - referenced dynamically
use Cpanel::Comet::Mock          ();
use Cpanel::AdminBin::Serializer ();

my $CHANNEL = 'securityadvisor';

# Overridden in tests
our $_ADVISOR_CLASS = 'Cpanel::Security::Advisor';

sub fetch_security_advice {
    local $Cpanel::Locale::Context::DEFAULT_OUTPUT_CONTEXT = 'html';    # we want links
    my $comet   = Cpanel::Comet::Mock->new();
    my $advisor = $_ADVISOR_CLASS->new( 'comet' => $comet, 'channel' => $CHANNEL );

    my ( $merged, @result ) = Capture::Tiny::capture_merged(
        sub {
            $advisor->generate_advice();
        }
    );

    if ( !$merged ) {
        warn $_ for grep { length } @result;
    }

    my $whm_url = _get_whm_url();

    my $ref = $comet->get_messages($CHANNEL);

    my @decoded = map { length() ? Cpanel::AdminBin::Serializer::Load($_) : () } @$ref;

    my @returned;

    foreach my $message (@decoded) {
        my $data = $message->{'data'} or next;
        my $type = $data->{'type'}    or next;

        if ( $type eq 'mod_advice' ) {
            my $advice = $data->{'advice'} or do {
                warn "“mod_advice” message from “$data->{'module'}” that lacked “advice”!";
                next;
            };

            foreach my $atype (qw(text suggestion)) {
                _convert_links_to_absolute_urls( $whm_url, \$advice->{$atype} ) if length $advice->{$atype};
            }

            push @returned, { %{$data}{ 'type', 'module', 'advice' } };
        }
        elsif ( $type eq 'mod_load' && $data->{'state'} != 1 ) {
            push @returned, { %{$data}{ 'type', 'module', 'message' } };
        }
        elsif ( $type eq 'mod_run' && $data->{'state'} == -1 ) {
            push @returned, { %{$data}{ 'type', 'module', 'message' } };
        }
    }

    return \@returned;
}

sub _convert_links_to_absolute_urls {
    my ( $url, $text_sr ) = @_;
    $$text_sr =~ s{href="\.\./}{href="$url/}g;
    return 1;
}

sub _get_whm_url {
    require Cpanel::SSL::Domain;
    my $ssl_domain = Cpanel::SSL::Domain::get_best_ssldomain_for_service('cpanel');
    return "https://$ssl_domain:2087";
}

1;
