package Cpanel::Config::userdata::Simple;

# cpanel - Cpanel/Config/userdata/Simple.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=head1 NAME

Cpanel::Config::userdata::Simple

=head1 DESCRIPTION

This is a simple wrapper API around the existing userdata functions.
The key difference being, is that it uses Cpanel::Exception to
verify/validate when the user has performed an invalid action.

NOTE: In the long run, it would be best to utilize the Cpanel::Transaction
system instead of duct-taping around ::Guard problems.

=cut

use strict;
use warnings;
use Cpanel::Exception               ();
use Cpanel::Config::userdata::Load  ();
use Cpanel::Config::userdata::Guard ();

=pod

=head2 B<get_cpanel_vhost_userdata( $user, $vhost )>

Retrieve vhost-specific userdata configuration.  This will
throw a Cpanel::Exception if an invalid user and/or vhosts
is supplied.

    INPUT
        scalar -- user name
        scalar -- domain name

    OUTPUT
        hash ref -- success
        throw Cpanel::Exception -- failure

=cut

sub get_cpanel_vhost_userdata {
    my $user  = shift;
    my $vhost = shift;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] )  unless defined $user;
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'vhost' ] ) unless defined $vhost;

    my $data = Cpanel::Config::userdata::Load::load_userdata( $user, $vhost );
    if ( scalar keys %$data == 0 ) {
        my $file = Cpanel::Config::userdata::Load::get_userdata_file_for_domain( $user, $vhost );
        die Cpanel::Exception::create(
            'UserdataLookupFailure',
            'Error loading data for user “[_1]” from file: [_2]',
            [ $user, $file ],
        );
    }

    return $data;
}

=pod

=head2 B<get_cpanel_userdata( $user )>

Retrieve the 'main' userdata configuration for a user.  This
is generally nothing more than a list of vhosts the user owns.
This will throw a Cpanel::Exception if an invalid user is
supplied or you don't have permission to access the data.

    INPUT
        scalar -- user name

    OUTPUT
        hash ref -- success
        throw Cpanel::Exception -- failure

=cut

sub get_cpanel_userdata {
    my $user = shift;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] ) unless defined $user;

    my $data = Cpanel::Config::userdata::Load::load_userdata($user);
    die Cpanel::Exception::create( 'InvalidParameter', 'You must specify a valid user.' ) unless keys %$data;

    return $data;
}

=pod

=head2 B<set_cpanel_vhost_userdata( $user, $vhost, { $key =E<gt> $value } )>

Update userdata configuration.  Will throw a Cpanel::Exception if a failure
occurs.  If the value of a key is undef, then the key will be deleted from
the userdata configuration.

    INPUT
        scalar -- user name
        scalar -- domain name
        hash ref -- keys and values to set
        hash ref -- (optional) additional parameters to this function itself
            - skip_userdata_cache_update

    OUTPUT
        truthy value -- success
        throw Cpanel::Exception -- failure

=cut

sub set_cpanel_vhost_userdata {
    my $user  = shift;
    my $vhost = shift;
    my $href  = shift;    # hashref of key-value pairs to set
    my $opts  = shift;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] )    unless defined $user;
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'vhost' ] )   unless defined $vhost;
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'hashref' ] ) unless defined $href;

    # Guard doesn't tell you if it failed to acquire a lock (CPANEL-1395).
    no warnings qw( redefine );
    require Cpanel::Logger;
    local *Cpanel::Logger::warn = sub { };

    my $guard = Cpanel::Config::userdata::Guard->new( $user, $vhost );
    my $data  = $guard->data();
    die Cpanel::Exception::create( 'InvalidParameter', 'You must specify a valid user and domain.' ) unless keys %$data;

    while ( my ( $key, $value ) = each(%$href) ) {
        if ( defined $value ) {
            $data->{$key} = $value;
        }
        else {
            delete $data->{$key};
        }
    }

    $guard->save()
      or die Cpanel::Exception::create( 'IO::FileWriteError', q{You do not have permission to update [asis,userdata] for domain “[_1]”.}, [$vhost] );

    $opts ||= {};
    if ( !$opts->{'skip_userdata_cache_update'} ) {
        require Cpanel::Config::userdata::UpdateCache;
        Cpanel::Config::userdata::UpdateCache::update( $user, { force => 1 } );
    }

    return 1;
}

=pod

=head1 CONFIGURATION AND ENVIRONMENT

The module requires no configuration files or environment variables.

=head1 INCOMPATIBILITIES

None reported.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited

=cut

1;
