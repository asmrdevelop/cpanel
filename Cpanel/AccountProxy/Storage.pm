package Cpanel::AccountProxy::Storage;

# cpanel - Cpanel/AccountProxy/Storage.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::AccountProxy::Storage

=head1 SYNOPSIS

    my $backend = Cpanel::AccountProxy::Storage::get_backend( \%cpuser );

    my $backend = Cpanel::AccountProxy::Storage::get_worker_backend( \%cpuser, 'Mail' );

    Cpanel::AccountProxy::Storage::set_backend( \%cpuser, $hostname );
    Cpanel::AccountProxy::Storage::set_worker_backend( \%cpuser, 'Mail', $hostname );

    Cpanel::AccountProxy::Storage::unset_backend( \%cpuser );
    Cpanel::AccountProxy::Storage::unset_worker_backend( \%cpuser, 'Mail' );

=head1 DESCRIPTION

This module interfaces with hash references that represent the contents
of cpuser files: it reads, sets, and unsets a user’s account-proxy
configuration, which is used to determine whether to tell various services
to answer requests locally or to forward them to a remote backend.

The backends can be either general or specific to a given worker type.
For example, if an account has a C<Mail> backend as well as a general
backend, then mail-related requests should be forwarded to the C<Mail>
backend, while other requests should go to the general backend.

If an account has only a general backend, then all requests—including
mail-related ones—should go there.

(It is a misconfiguration for an account to have a worker backend but
no general backend. This module enforces that limitation.)

=cut

#----------------------------------------------------------------------

my $_GENERAL_KEY = 'PROXY_BACKEND';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 validate_proxy_backend_types_or_die( \@TYPES )

Compares the specified backend types and throws an exception if any of them are not
recognized worker types.

=cut

sub validate_proxy_backend_types_or_die ($types_ar) {

    require Cpanel::LinkedNode::Worker::GetAll;
    require Cpanel::Set;

    my @recognized = Cpanel::LinkedNode::Worker::GetAll::RECOGNIZED_WORKER_TYPES();
    my @invalid    = Cpanel::Set::difference(
        $types_ar,
        \@recognized,
    );

    if (@invalid) {
        die "Invalid service group name(s) (@invalid); recognized names are: @recognized\n";
    }

    return;
}

=head2 get_service_proxy_backends_for_user( $USERNAME )

A convenience wrapper function that loads the user file for the specified username and
extracts all of the defined backends.

=cut

sub get_service_proxy_backends_for_user ($username) {

    require Cpanel::Config::LoadCpUserFile;
    require Cpanel::AccountProxy::Storage;
    require Cpanel::LinkedNode::Worker::GetAll;

    my $cpuser = Cpanel::Config::LoadCpUserFile::load_or_die($username);

    my @backends;

    if ( my $general = Cpanel::AccountProxy::Storage::get_backend($cpuser) ) {
        push @backends, {
            service_group => undef,
            backend       => $general,
        };

        for my $svc_group ( Cpanel::LinkedNode::Worker::GetAll::RECOGNIZED_WORKER_TYPES() ) {
            if ( my $backend = Cpanel::AccountProxy::Storage::get_raw_worker_backend( $cpuser, $svc_group ) ) {
                push @backends, {
                    service_group => $svc_group,
                    backend       => $backend,
                };
            }
        }
    }

    return \@backends;
}

=head2 $hostname_or_undef = get_backend( \%CPUSER )

Reads \%CPUSER for the account’s general proxy backend.
Returns the stored hostname of that backend, or undef if there is none.

=cut

sub get_backend ($cpuser_hr) {

    return $cpuser_hr->{$_GENERAL_KEY};
}

=head2 $hostname_or_undef = get_worker_backend( \%CPUSER, $WORKER_TYPE )

Like C<get_backend()> but fetches a worker backend instead.
If there is no such backend, then this returns the same value as
C<get_backend()>.

=cut

sub get_worker_backend ( $cpuser_hr, $worker_type ) {

    return get_raw_worker_backend( $cpuser_hr, $worker_type ) // get_backend($cpuser_hr);
}

=head2 $hostname_or_undef = get_raw_worker_backend( \%CPUSER, $WORKER_TYPE )

Like C<get_worker_backend()> but does B<NOT> fall back to C<get_backend()>’s
value in the event that $WORKER_TYPE lacks its own defined backend. Useful
for backup purposes.

=cut

sub get_raw_worker_backend ( $cpuser_hr, $worker_type ) {
    return $cpuser_hr->{ _get_worker_key($worker_type) };
}

#----------------------------------------------------------------------

=head2 set_backend( \%CPUSER, $HOSTNAME )

Sets an account’s general backend proxy hostname in %CPUSER.

Returns nothing.

=cut

sub set_backend ( $cpuser_hr, $hostname ) {
    _validate_hostname($hostname);

    $cpuser_hr->{$_GENERAL_KEY} = $hostname;

    return;
}

=head2 set_worker_backend( \%CPUSER, $WORKER_TYPE, $HOSTNAME )

Like C<set_backend()> but sets a worker backend instead.
%CPUSER B<must> already contain a general backend, or else an
exception is thrown.

=cut

sub set_worker_backend ( $cpuser_hr, $worker_type, $hostname ) {
    _validate_hostname($hostname);

    if ( !get_backend($cpuser_hr) ) {
        die "Set a general backend before setting “$worker_type” backend!";
    }

    $cpuser_hr->{ _get_worker_key($worker_type) } = $hostname;

    return;
}

#----------------------------------------------------------------------

=head2 $old_hostname = unset_backend( \%CPUSER )

Removes any general proxy backend from %CPUSER.

Returns either the previously-stored hostname, or undef if there
was none.

%CPUSER B<must not> contain any worker backends, or else an
exception is thrown.

=cut

sub unset_backend ($cpuser_hr) {
    if ( my @workers = _get_workers($cpuser_hr) ) {
        die "Unset all workers (@workers) before unsetting general backend!";
    }

    return delete $cpuser_hr->{$_GENERAL_KEY};
}

=head2 $old_hostname = unset_worker_backend( \%CPUSER, $WORKER_TYPE )

Like C<unset_backend()> but for a worker proxy.

=cut

sub unset_worker_backend ( $cpuser_hr, $worker_type ) {

    return delete $cpuser_hr->{ _get_worker_key($worker_type) };
}

#----------------------------------------------------------------------

sub _validate_hostname ($hostname) {
    die "empty hostname is invalid!" if !length $hostname;

    return;
}

sub _get_workers ($cpuser_hr) {
    return map { m<\A$_GENERAL_KEY-(.+)> ? $1 : () } keys %$cpuser_hr;
}

sub _get_worker_key ($worker_type) {
    return "$_GENERAL_KEY-$worker_type";
}

1;
