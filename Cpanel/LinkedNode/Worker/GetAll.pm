package Cpanel::LinkedNode::Worker::GetAll;

# cpanel - Cpanel/LinkedNode/Worker/GetAll.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Worker::GetAll

=head1 DESCRIPTION

A convenience module for reading an account’s full worker-node
configuration.

=cut

#----------------------------------------------------------------------

use Cpanel::LinkedNode::User            ();
use Cpanel::LinkedNode::Worker::Storage ();

# Exposed for testing:
our @_RECOGNIZED_WORKER_TYPES = qw( Mail );

#----------------------------------------------------------------------

=head1 CONSTANTS

=head2 @types = RECOGNIZED_WORKER_TYPES()

A list of all worker node types that cPanel & WHM recognizes.

=cut

sub RECOGNIZED_WORKER_TYPES { return @_RECOGNIZED_WORKER_TYPES }

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @worker_data = get_all_from_cpuser( $CPUSER_OBJ )

Returns all data for each of a user’s configured worker nodes.

$CPUSER_OBJ is a L<Cpanel::Config::CpUser::Object> instance.

The return is a list of hash references, each of which contains:

=over

=item * C<worker_type> - the worker node type (e.g., C<Mail>)

=item * C<alias> - the worker node’s alias

=item * C<api_token> - the user’s API token to access that worker node

=item * C<configuration> - a L<Cpanel::LinkedNode::User::Configuration>
object that represents that worker node’s configuration

=back

In scalar context, this returns the number of hash references that
would have been returned in list context.

This throws if any worker node configuration is inaccessible.
(That really should not happen and indicates a significant
misconfiguration, e.g., wrong filesystem permissions.)

=cut

sub get_all_from_cpuser ($cpuser_hr) {

    my @ret;

    my %alias_conf;

    for my $worker_type ( RECOGNIZED_WORKER_TYPES() ) {

        my $hr = _get_from_cpuser( $cpuser_hr, $worker_type, \%alias_conf );

        push @ret, $hr if $hr;
    }

    return @ret;
}

#----------------------------------------------------------------------

=head2 @worker_data = get_aliases_and_tokens_from_cpuser( \%CPUSER_DATA )

Like C<get_all_from_cpuser()> but doesn’t return C<configuration>.

=cut

sub get_aliases_and_tokens_from_cpuser ($cpuser_hr) {

    my @ret;

    for my $worker_type ( RECOGNIZED_WORKER_TYPES() ) {

        my $ht_ar = Cpanel::LinkedNode::Worker::Storage::read( $cpuser_hr, $worker_type );

        if ($ht_ar) {
            push @ret, {
                worker_type => $worker_type,
                alias       => $ht_ar->[0],
                api_token   => $ht_ar->[1],
            };
        }
    }

    return @ret;
}

#----------------------------------------------------------------------

=head2 $type_config_hr = get_lookup_from_cpuser( \%CPUSER_DATA )

A convenience wrapper around C<get_all_from_cpuser()> that
transforms the data to a hash. The hash contains a key for each
worker type (e.g., C<Mail>); if the given %CPUSER_DATA indicates a worker
of that type, then the value of the corresponding value in the hash will be
a hash reference with C<alias>, C<api_token>, and C<configuration>
(cf. C<get_all_from_cpuser()>); otherwise the value will be undef.

A reference to the hash is returned.

For example:

    {
        Mail => {
            alias => 'thealias',
            api_token => 'ABCDEFG..',
            configuration => $blessed_object,
        },

        OtherType => undef,
    }

=cut

sub get_lookup_from_cpuser ($cpuser_hr) {
    my @worker_data = get_all_from_cpuser($cpuser_hr);

    my %lookup = map { delete $_->{'worker_type'} => $_ } @worker_data;

    $_ ||= undef for @lookup{ RECOGNIZED_WORKER_TYPES() };

    return \%lookup;
}

#----------------------------------------------------------------------

=head2 $conf_hr = get_one_from_cpuser( $WORKER_TYPE, \%CPUSER_DATA )

Like C<get_all_from_cpuser()> but looks fora specific $WORKER_TYPE (e.g.,
C<Mail>).

Returns either undef (if %CPUSER_DATA contains no such worker) or a hash
reference like one of the ones that C<get_all_from_cpuser()> returns.

=cut

sub get_one_from_cpuser ( $worker_type, $cpuser_hr ) {
    return _get_from_cpuser( $cpuser_hr, $worker_type, undef );
}

#----------------------------------------------------------------------

sub _get_from_cpuser ( $cpuser_hr, $worker_type, $alias_cache_hr ) {    ## no critic qw(ManyArgs) - mis-parse
    my $ht_ar = Cpanel::LinkedNode::Worker::Storage::read( $cpuser_hr, $worker_type );

    return $ht_ar && do {
        my ( $alias, $token ) = @$ht_ar;

        my $worker_conf = $alias_cache_hr && $alias_cache_hr->{$alias};

        $worker_conf ||= Cpanel::LinkedNode::User::get_node_configuration($alias);

        if ($alias_cache_hr) {
            $alias_cache_hr->{$alias} ||= $worker_conf;
        }

        {
            worker_type   => $worker_type,
            alias         => $alias,
            api_token     => $token,
            configuration => $worker_conf,
        };
    };
}

1;
