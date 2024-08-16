package Cpanel::Config::LoadDemoUsers;

# cpanel - Cpanel/Config/LoadDemoUsers.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles                  ();
use Cpanel::Transaction::File::RawReader ();

=head1 NAME

Cpanel::Config::LoadDemoUsers

=head1 SYNOPSIS

my $demo_users = Cpanel::Config:LoadDemoUsers::load();

my $demo_users_hashref = Cpanel::Config::LoadDemoUsers::load_as_hash();

=head1 DESCRIPTION

Provides read access to the list of demo users.

=head1 SUBROUTINES

=over

=item load()

Returns an arrayref containing the demo user names as strings.

If there are no demo users an empty arrayref is returned;

=item load_as_hashref()

Returns a hashref where the keys are the demo user names. All values are 1.

Returns an empty hashref when no demo users exist.

=back

=cut

our $root_path = '';    # for testing

sub load {
    my @demo_users;

    my $br = Cpanel::Transaction::File::RawReader->new( 'path' => $root_path . $Cpanel::ConfigFiles::DEMOUSERS_FILE );

    if ( $br->length() ) {
        foreach my $line ( split( m{\s}, ${ $br->get_data() } ) ) {
            chomp $line;

            push( @demo_users, $line );
        }
    }

    return \@demo_users;
}

sub load_as_hashref {
    my $temp_ar    = Cpanel::Config::LoadDemoUsers::load();
    my %demo_users = map { $_ => 1 } @$temp_ar;
    return \%demo_users;
}

1;
