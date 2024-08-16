package Whostmgr::Packages::Find;

# cpanel - Whostmgr/Packages/Find.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AcctUtils::Load   ();
use Whostmgr::Packages::Fetch ();
use Whostmgr::Packages::Mod   ();

sub find_matching_packages {
    my %OPTS = @_;

    my $exclude = $OPTS{'exclude'};

    my $want = $OPTS{'want'} || 'creatable';

    # $OPTS{'settings'} should be a hash ref of the plan settings to match against

    # copy the hash to iron out differences between packages and accounts
    my %settings = %{ $OPTS{'settings'} };

    Whostmgr::Packages::Mod::convert_cpuser_to_package_keys( \%settings );

    Cpanel::AcctUtils::Load::loadaccountcache();

    my $pkglist_ref = Whostmgr::Packages::Fetch::fetch_package_list( 'want' => $want, 'test_with_less_packages' => { 'count' => 1, 'package' => $exclude } );

    # We don't check for conflicts with the default package.
    delete $pkglist_ref->{'default'};

    # pkglist_ref is a hashref of packages with the name as the key
    #       'bob' => {
    #           'MAXFTP' => '88',
    #           'FEATURELIST' => 'default',
    #           'QUOTA' => '9000',
    #           'CPMOD' => 'x3',
    #           'MAXADDON' => '88',
    #           'MAXSUB' => '88',
    #           'MAXLST' => '88',
    #           'MAXPARK' => '88',
    #           'CGI' => 'y',
    #           'BWLIMIT' => '9000',
    #           'HASSHELL' => 'y',
    #           'IP' => 'y',
    #           'MAXPOP' => '88',
    #           'MAXSQL' => '88',
    #           'LANG' => 'en'
    #       },

    return [
        sort  { scalar keys %{$b} <=> scalar keys %{$a} }                                                                                              # We return the best match first
          map { _matches_package_query( $pkglist_ref->{$_}, \%settings ) ? ( { 'name' => $_, %{ $pkglist_ref->{$_} } } ) : () } keys %{$pkglist_ref}
    ];
}

sub _matches_package_query {
    my ( $package_data_ref, $query_ref ) = @_;

    # CPANEL-39050: Return all packages when no search query is provided.
    return 1 if not scalar keys %{$query_ref};

    # two packages can't match if they have different extensions
    return _extensions_match( $package_data_ref, $query_ref ) && _key_values_match( $package_data_ref, $query_ref );
}

sub _key_values_match {
    my ( $pkghash, $cpuserhash ) = @_;

    foreach my $key ( keys %{$pkghash} ) {
        next     if $key eq 'LOCALE' || $key eq 'LANG';                  #user modifiable
        next     if !exists( $cpuserhash->{$key} );
        return 0 if ( lc $pkghash->{$key} ne lc $cpuserhash->{$key} );
    }
    return 1;
}

sub _extensions_match {
    my ( $pkghash, $cpuserhash ) = @_;

    my $pkg_extensions = '';
    if ( $pkghash->{'_PACKAGE_EXTENSIONS'} ) {
        $pkg_extensions = join( ' ', sort( split( /\s+/, $pkghash->{'_PACKAGE_EXTENSIONS'} ) ) );
    }

    my $user_extensions = '';
    if ( $cpuserhash->{'_PACKAGE_EXTENSIONS'} ) {
        $user_extensions = join( ' ', sort( split( /\s+/, $cpuserhash->{'_PACKAGE_EXTENSIONS'} ) ) );
    }

    return $pkg_extensions eq $user_extensions ? 1 : 0;
}

1;

__END__

=head1 CLI Example

REMOTE_USER=root perl -MData::Dumper -MWhostmgr::Packages::Find -e "print Dumper( Whostmgr::Packages::Find::find_matching_packages( 'want' => 'all', 'settings' => { 'MAXFTP' => 88, 'FEATURELIST' => 'default', 'QUOTA'=> 9000, 'CPMOD'=>'x3', 'MAXADDON' => '88', 'MAXSUB' => '88', 'MAXLST' => '88','MAXPARK' => '88', 'CGI' => 'y','BWLIMIT' => '9000','HASSHELL' => 'y','IP' => 'y', 'MAXPOP' => '88','MAXSQL' => '88'   }, 'exclude' => 'undefined') );"
