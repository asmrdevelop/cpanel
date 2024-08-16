package Cpanel::DB;

# cpanel - Cpanel/DB.pm                            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DB::Prefix       ();
use Cpanel::DB::Prefix::Conf ();
use Cpanel::LoadModule       ();

*use_prefix = *Cpanel::DB::Prefix::Conf::use_prefix;

sub get_prefix {
    return q<> if !Cpanel::DB::Prefix::Conf::use_prefix();
    return Cpanel::DB::Prefix::username_to_prefix( _get_cpanel_user_for_prefix() );
}

#TODO: See if this can be simplified or removed entirely.
sub _get_cpanel_user_for_prefix {
    return $ENV{'TEAM_USER'} ? $Cpanel::user : ( $ENV{'REMOTE_USER'} || $Cpanel::user );
}

#Add the prefix if the server uses DB prefixing
#AND the $name doesn't already have the running user's prefix.
#
#NOTE: Adding the prefix only if the name isn't already prefixed seems
#less than ideal; TODO: implement APIs that consistently add the prefix.
sub add_prefix_if_name_and_server_need {
    my ($name) = @_;

    if ( Cpanel::DB::Prefix::Conf::use_prefix() ) {
        my $cpuser = _get_cpanel_user_for_prefix();
        $name = Cpanel::DB::Prefix::add_prefix_if_name_needs( $cpuser, $name );
    }

    return $name;
}

#XXX: Please do not use this anymore; instead, instantiate Cpanel::DB::Map directly.
sub get_map {
    my ($args) = @_;
    my $cpuser = $args->{'cpuser'} || _get_cpanel_user_for_prefix();
    my $dbtype = $args->{'dbtype'} || 'MYSQL';
    Cpanel::LoadModule::load_perl_module('Cpanel::DB::Map');
    my $map = Cpanel::DB::Map->new( { cpuser => $cpuser, db => $dbtype } );
    return $map;
}

1;
