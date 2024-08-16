package Cpanel::LinkedNode::Convert::FromDistributed::Mail::Backend;

# cpanel - Cpanel/LinkedNode/Convert/FromDistributed/Mail/Backend.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::FromDistributed::Mail::Backend

=head1 DESCRIPTION

This module contains individual pieces of functionality for
L<Cpanel::LinkedNode::Convert::FromDistributed::Mail>.

B<IMPORTANT:> Please B<DON’T> call this module from anywhere else.
Refactor whatever functionality you need instead.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::Exim::ManualMX                                ();
use Cpanel::Hostname                                      ();
use Cpanel::LinkedNode::Convert::Common::Mail::Backend    ();
use Cpanel::LinkedNode::Convert::Common::Mail::FromRemote ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

B<IMPORTANT:> See L<Cpanel::LinkedNode::Convert::ToDistributed::Mail::Backend>
for the naming conventions to follow here.

=head2 step__remove_manual_mx ( \%INPUT, $STATE_OBJ )

%INPUT are the args given to the conversion;
$STATE_OBJ is a L<Cpanel::LinkedNode::Convert::FromDistributed::Mail::State>
instance.

This removes the account’s local manual-MX entries and stores the
old values in C<$STATE{'old_mx'}>.

%INPUT must contain C<username>.

=cut

sub step__remove_manual_mx ( $input_hr, $state_obj ) {
    my $domains_ar = Cpanel::LinkedNode::Convert::Common::Mail::Backend::get_mail_domains_for_step($input_hr);

    $state_obj->set( 'old_source_manual_mx', Cpanel::Exim::ManualMX::unset_manual_mx_redirects($domains_ar) );

    return;
}

=head2 undo__remove_manual_mx ( \%INPUT, $STATE_OBJ )

%INPUT are the args given to the conversion;
$STATE_OBJ is a L<Cpanel::LinkedNode::Convert::FromDistributed::Mail::State>
instance.

C<step__remove_manual_mx()>’s undo logic.

=cut

sub undo__remove_manual_mx ( $, $state_obj ) {
    my $old_mx_hr = $state_obj->get('old_source_manual_mx');

    my @none = grep { !defined $old_mx_hr->{$_} } keys %$old_mx_hr;

    my %set = %$old_mx_hr;
    delete @set{@none};

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

=head2 step__set_up_source_manual_mx ( \%INPUT, $STATE_OBJ )

This sets up the child node’s manual MX so that mail sent to the
child node will always route to the parent, regardless of DNS caching.

%INPUT are the args given to the conversion;
$STATE_OBJ is a L<Cpanel::LinkedNode::Convert::FromDistributed::Mail::State>
instance.

%INPUT must contain C<username>, and $STATE_OBJ must contain C<node_obj>.

This function sets C<old_source_manual_mx> in $STATE_OBJ but otherwise
returns nothing.

=cut

sub step__set_up_source_manual_mx ( $input_hr, $state_obj ) {
    return Cpanel::LinkedNode::Convert::Common::Mail::FromRemote::set_up_source_manual_mx(
        $input_hr,
        $state_obj,
        Cpanel::Hostname::gethostname(),
    );
}

=head2 step__set_up_child_service_proxy ( \%INPUT, $STATE_OBJ )

This sets up the child node’s service proxying so that POP3/IMAP
traffic sent to the child node will proxy to the parent. This prevents
stale DNS caches from sending users to the (now-former) mailbox server.

%INPUT are the args given to the conversion;
$STATE_OBJ is a L<Cpanel::LinkedNode::Convert::FromDistributed::Mail::State>
instance.

%INPUT must contain C<username>, and $STATE_OBJ must contain C<node_obj>
(a L<Cpanel::LinkedNode::Privileged::Configuration> instance).

This function sets C<child_old_proxy> (the return value from WHM API v1
C<get_service_proxy_backends()>) in $STATE_OBJ but otherwise
returns nothing.

=cut

sub step__set_up_source_service_proxy ( $input_hr, $state_obj ) {
    return Cpanel::LinkedNode::Convert::Common::Mail::FromRemote::set_up_source_service_proxy(
        $input_hr,
        $state_obj,
        Cpanel::Hostname::gethostname(),
    );
}

1;
