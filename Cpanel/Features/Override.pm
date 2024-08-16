package Cpanel::Features::Override;

# cpanel - Cpanel/Features/Override.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Features::Override

=head1 SYNOPSIS

    my $what_disables = Cpanel::Features::Override::somefeature->what_disables();

    if ($what_disables) {

        # The feature is disabled.
    }
    else {

        # Nothing disables the feature; can proceed to check the user’s
        # local configuration.
    }

=head1 DESCRIPTION

This is a base class that checks for configuration parameters that override
the normal user feature configuration.

It defines two related pieces of functionality:

=over

=item * Define a feature’s enabledness as requiring the feature’s
enabledness on the account’s relevant child node, if any.

=item * Define a feature’s enabledness as a function of a given role’s
enabledness.

=back

=head1 HOW TO CREATE A SUBCLASS OF THIS MODULE

Name your module after the feature (e.g., C<spamassassin>
becomes L<Cpanel::Features::Override::spamassassin>). Override
whichever of the below-indicated overridable methods you will.
Profit!

=cut

#----------------------------------------------------------------------

=head1 CLASS METHODS

=head2 $disabler = I<CLASS>->what_disables()

Returns the reason, if any, why the feature should be considered off:

=over

=item * C<child_node>, to indicate that the feature is off on the
child node.

=item * C<role>, to indicate that the required local role is off.

=item * undef, if nothing we checked prevents the feature from being on.

=back

=cut

sub what_disables ($class) {
    if ( my $workload = $class->_CHILD_WORKLOAD() ) {
        require Cpanel::LinkedNode::Worker::User;

        my $feature_name = $class->_feature_name();

        my $result = Cpanel::LinkedNode::Worker::User::call_worker_uapi( 'Mail', 'Features', 'has_feature', { name => $feature_name } );

        return 'child_node' if $result && !$result->data();
    }

    if ( my $role = $class->_LOCAL_ROLE() ) {
        require Cpanel::Server::Type::Profile::Roles;
        return 'role' if !Cpanel::Server::Type::Profile::Roles::is_role_enabled($role);
    }

    return undef;
}

sub _feature_name ($class) {
    my $name = $class;
    my $pkg  = __PACKAGE__;

    my $is_invalid;

    $name =~ s<\A\Q$pkg\E::><> or $is_invalid = 1;

    $is_invalid ||= ( $name =~ tr<:><> );

    if ($is_invalid) {
        require Carp;
        Carp::confess( sprintf "Invalidly-named %s subclass: %s", __PACKAGE__, $class );
    }

    return $name;
}

=head1 PROTECTED METHODS

=head2 $role = I<CLASS>->_LOCAL_ROLE()

Can be overridden; defines a role that the feature requires.

=cut

sub _LOCAL_ROLE {
    return undef;
}

=head2 $workload = I<CLASS>->_CHILD_WORKLOAD()

Can be overridden; gives a child workload (e.g., C<Mail>) to check
for the feature.  If the feature is off on the child, then it’s off
locally as well. Default is undef.

=cut

# Might as well reuse …
*_CHILD_WORKLOAD = *_LOCAL_ROLE;

1;
