# cpanel - Cpanel/Security/Advisor/Assessors/Elevate.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Security::Advisor::Assessors::Elevate;

=head1 NAME

Cpanel::Security::Advisor::Assessors::Elevate

=head1 SYNOPSIS

    my $secadv = Cpanel::Security::Advisor->new(comet => $comet, channel => $channel);

    my $assessor = Cpanel::Security::Advisor::Assessors::Elevate->new($secadv);
    $assessor->generate_advice();

=head1 DESCRIPTION

Security Advisor assessor (subclass of L<Cpanel::Security::Advisor::Assessors>)
which uses L<Cpanel::Elevate> to download the cPanel ELevate script and run it
in check mode to inform system administrators that this script exists and
whether certain conditions need to be resolved to allow this process to
proceed.

=cut

use cPstrict;

use parent 'Cpanel::Security::Advisor::Assessors';

use Cpanel::OS        ();
use Cpanel::Elevate   ();
use Cpanel::Exception ();

use Try::Tiny;

use constant version           => '1.01';
use constant estimated_runtime => 5;

=head1 METHODS

=head2 $assessor->generate_advice()

Implements base class method to notify whether the system is eligible for such
an upgrade and what might prevent it from going forward.

=cut

sub generate_advice ($self) {

    $self->{'elevate_obj'} = Cpanel::Elevate->new( check_file => '/var/cpanel/elevate-blockers.security-advisor' );

    if ( Cpanel::OS::can_be_elevated() && !$self->{'elevate_obj'}->noc_recommendations() ) {

        my @candidates = Cpanel::OS::can_elevate_to()->@*;
        my $target     = _pick_best_candidate( \@candidates );

        $self->_generate_elevate_eligibility_advice( $target, @candidates );
        $self->_generate_elevate_dry_run_advice($target);
    }

    return 1;
}

# report whether the OS is eligible for ELevate
sub _generate_elevate_eligibility_advice ( $self, $target, @candidates ) {
    if ($target) {

        # TODO: additional(?) notification when current OS is about to reach EOL
        # TODO: if multiple candidates are present, we should list them in the suggestion as alternatives
        ( $target, @candidates ) = map { Cpanel::OS::lookup_pretty_distro($_) } ( $target, @candidates );
        $self->add_info_advice(
            'key'          => 'Elevate_eligibility',
            'block_notify' => 1,
            'text'         => $self->_lh->maketext("It may be possible to upgrade the operating system on your server to a newer major release without migrating to a new server."),
            'suggestion'   => $self->_lh->maketext( "Consider testing the cPanel ELevate utility to upgrade the operating system to [_1] before the [output,url,_2,current system reaches End of Life]. For more information, see [output,url,_3,the utility’s website].", $target, 'https://go.cpanel.net/deprecation', 'https://go.cpanel.net/ELevate' ),
        );
    }

    return;
}

# report blockers
sub _generate_elevate_dry_run_advice ( $self, $target ) {
    if ($target) {

        my $elevate = $self->{'elevate_obj'};

        try {
            $elevate->update();
        }
        catch {
            say STDERR Cpanel::Exception::get_string($_);
        };

        $elevate->check();    # XXX How do we know that check() ran OK?

        $target = Cpanel::OS::lookup_pretty_distro($target);

        my $blocker_file = $elevate->dump_blocker_file();
        my @blockers     = map { $_->{'msg'} // () } $blocker_file->{'blockers'}->@*;

        if ( !@blockers ) {
            $self->add_good_advice(
                'key'  => 'Elevate_target_blockers',
                'text' => $self->_lh->maketext( "The system detected no issues preventing cPanel ELevate from upgrading the system to [_1].", $target ),
            );
        }
        else {
            $self->add_info_advice(    # TODO: 'info' in 106, 'warn' in 108, 'bad' in 110
                'key'        => 'Elevate_target_blockers',
                'text'       => $self->_lh->maketext( "The system detected the following issues which would prevent cPanel ELevate from upgrading the system to [_1]:", $target ),
                'suggestion' => _make_html_unordered_list(@blockers),
            );
        }
    }

    return;
}

# XXX duplicated from the PHP assessor, then modified trivially
sub _make_html_unordered_list (@items) {
    my $output = '<ul>';
    foreach my $item (@items) {
        $output .= "<li>$item</li>";
    }
    $output .= '</ul>';

    return $output;
}

# Decides which of the given candidates in the given arrayref is the best recommendation for upgrade, if any.
# If no candidate OS is to be recommended, the empty string is returned.
# If a candidate is recommended, it is removed from the arrayref and returned.
# Additionally, this function is allowed to otherwise re-order the elements of the arrayref, the intent of doing so being to put better secondary options not chosen ahead of others.
sub _pick_best_candidate ($candidates_ar) {
    return defined $candidates_ar->[0] ? shift $candidates_ar->@* : '';    # TODO: for now, just return the first entry or an empty string
}

1;
