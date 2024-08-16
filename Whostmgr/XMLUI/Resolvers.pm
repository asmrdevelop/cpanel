
package Whostmgr::XMLUI::Resolvers;

use strict;

use Whostmgr::Resolvers  ();
use Whostmgr::XMLUI      ();
use Whostmgr::ApiHandler ();

sub setresolvers {
    my %OPTS = @_;
    my @NAMESERVERS;
    for ( 1 .. 3 ) {
        if ( $OPTS{ 'nameserver' . $_ } ) {
            push @NAMESERVERS, $OPTS{ 'nameserver' . $_ };
        }
    }
    my ( $status, $statusmsg, $msgref, $warnref ) = Whostmgr::Resolvers::setupresolvers(@NAMESERVERS);

    my @RSD = ( { 'status' => $status, 'statusmsg' => $statusmsg, 'warns' => $warnref => 'msgs' => $msgref } );
    Whostmgr::XMLUI::xmlencode( \@RSD );

    my %RS;
    $RS{'setresolvers'} = \@RSD;

    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'setresolvers', 'NoAttr' => 1 );

}

1;
