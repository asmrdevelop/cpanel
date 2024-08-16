package Cpanel::LinkedNode::Convert::ToDistributed::Mail::Backend;

# cpanel - Cpanel/LinkedNode/Convert/ToDistributed/Mail/Backend.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::ToDistributed::Mail::Backend

=head1 DESCRIPTION

This module contains individual pieces of functionality for
L<Cpanel::LinkedNode::Convert::ToDistributed::Mail>.

B<IMPORTANT:> Please B<DON’T> call this module from anywhere else.
Refactor whatever functionality you need instead.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::LinkedNode::Convert::Common::Mail::Backend ();
use Cpanel::Exim::ManualMX                             ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

B<PLEASE> honor the following naming conventions:

=over

=item * Functions that implement steps in from-distributed conversion
are named with the C<step__> prefix.

=item * Rollback functions that complement C<step__> functions are named
with the C<undo__> prefix instead of C<step__> but otherwise have the same
name.

=back

=head2 step__set_up_manual_mx ( \%INPUT, $STATE_OBJ )

%INPUT are the arguments given to the conversion;
$STATE_OBJ is a L<Cpanel::LinkedNode::Convert::FromDistributed::Mail::State>
instance.

This sets up a manual MX entry for each of the user’s domains that can
receive mail. It stores any old values in $STATE_OBJ’s C<old_mx>.

%INPUT must contain C<username> (a string), and $STATE_OBJ must contain
C<node_obj> (a L<Cpanel::LinkedNode::Privileged::Configuration> instance).

=cut

sub step__set_up_manual_mx ( $input_hr, $state_obj ) {
    my $domains_ar = Cpanel::LinkedNode::Convert::Common::Mail::Backend::get_mail_domains_for_step($input_hr);

    my $hostname = $state_obj->get('target_node_obj')->hostname();

    my %new_mx = map { $_ => $hostname } @$domains_ar;

    $state_obj->set( old_local_manual_mx => Cpanel::Exim::ManualMX::set_manual_mx_redirects( \%new_mx ) );

    return;
}

=head2 undo__set_up_manual_mx ( \%INPUT, $STATE_OBJ )

$STATE_OBJ is a L<Cpanel::LinkedNode::Convert::FromDistributed::Mail::State>
instance. It must contain C<old_mx>.

C<step__set_up_manual_mx()>’s undo logic.

=cut

sub undo__set_up_manual_mx ( $, $state_obj ) {
    my $old_mx_hr = $state_obj->get('old_local_manual_mx');
    my @undo      = grep { !defined $old_mx_hr->{$_} } keys %$old_mx_hr;

    my %set = %$old_mx_hr;
    delete @set{@undo};

    if (@undo) {
        try {
            Cpanel::Exim::ManualMX::unset_manual_mx_redirects( \@undo );
        }
        catch {
            @undo = sort @undo;
            warn "Failed to unset manual MX (@undo): $_";
        };
    }

    if (%set) {
        try {
            Cpanel::Exim::ManualMX::set_manual_mx_redirects( \%set );
        }
        catch {
            my @show = map { $_ => $set{$_} } sort keys %set;
            warn "Failed to restore manual MX (@show): $_";
        };
    }

    return;
}

1;

