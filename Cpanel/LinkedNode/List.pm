package Cpanel::LinkedNode::List;

# cpanel - Cpanel/LinkedNode/List.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::List

=head1 SYNOPSIS

    my $nodes_ar = Cpanel::LinkedNode::List::list_user_worker_nodes();

=cut

#----------------------------------------------------------------------

use Cpanel::LinkedNode::AccountCache ();
use Cpanel::Config::LoadCpUserFile   ();
use Cpanel::Config::Users            ();
use Cpanel::LoadFile                 ();
use Cpanel::PromiseUtils             ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $nodes_ar = list_user_worker_nodes()

Returns a reference to an array of hash references. Each hash reference
describes a specific user-worker relationship and contains the following:

=over

=item * C<user> - the user’s name

=item * C<type> - the worker type (e.g., C<Mail>)

=item * C<alias> - the worker’s alias

=back

NB: For now this excludes the API token. It could be made to include it,
but any passthrough callers (e.g., APIs) should be updated to withhold the
token.

=cut

sub list_user_worker_nodes {
    my $cache = _get_cache_sync();

    my $parent_data_hr = $cache->get_all_parent_data();

    my @results;

    for my $un ( keys %$parent_data_hr ) {
        for my $workload ( keys %{ $parent_data_hr->{$un} } ) {
            push @results, {
                user  => $un,
                type  => $workload,
                alias => $parent_data_hr->{$un}{$workload},
            };
        }
    }

    return \@results;
}

sub _get_cache_sync {
    my $p = Cpanel::LinkedNode::AccountCache->new_p();

    return Cpanel::PromiseUtils::wait_anyevent($p)->get();
}

=head2 $nodes_ar = list_user_workloads()

Returns a reference to an array of hash references. Each hash reference
describes a specific user-worker relationship and contains the following:

=over

=item * C<user> - the user’s name

=item * C<workload_type> - the worker type (e.g., C<Mail>)

=back

=cut

sub list_user_workloads {
    my $cache = _get_cache_sync();

    my $child_data_hr = $cache->get_all_child_workloads();

    my @results;

    for my $un ( keys %$child_data_hr ) {
        push( @results, map { { user => $un, workload_type => $_ } } @{ $child_data_hr->{$un} } );
    }

    return \@results;
}

=head2 @workloads = get_workloads_for_user($USERNAME)

Returns a list of the workload types for a user.
In scalar context this returns the number of items that would have
been returned in list context.

As a special case, if $USERNAME is falsy, empty/0 is returned.

If $USERNAME does not refer to a system account, an exception is thrown.

=over

=item * C<username> - the user’s name, or a falsy value

=back

=cut

sub get_workloads_for_user ($username) {
    my @results = ();

    # This doesn’t use the cache because it’s probably simpler
    # just to parse the cpuser file.

    return @results unless $username;

    my $cpuser_hr = _get_userfile_property( $username, 'CHILD_WORKLOADS' );

    push @results, $cpuser_hr->child_workloads() if $cpuser_hr;

    return @results;
}

=head2 $nodes_ar = _get_userfile_property($user)

Returns cpuser_hr if the property is found in the file.

=over

=item * C<username> - the user’s name

=item * C<property> - the property name to search against

=back

=cut

sub _get_userfile_property ( $username, $property ) {
    my $dir = $Cpanel::ConfigFiles::cpanel_users;

    local $@;

    my $path = "$dir/$username";
    my $cpuser_hr;

    warn if !eval {

        # For a manually created reseller without a domain, this file
        # will not exist and its absence should not trigger a warning.
        my $content = Cpanel::LoadFile::load_if_exists($path);

        # XXX This avoids the overhead of parsing each cpuser file,
        # but we should replace it with something more efficient.
        if ( -1 != index( $content, $property ) ) {
            $cpuser_hr = Cpanel::Config::LoadCpUserFile::parse_cpuser_file_buffer($content);
        }

        1;
    };

    return $cpuser_hr;
}

# For testing:
*_get_cpuser_names = *Cpanel::Config::Users::getcpusers;

1;
