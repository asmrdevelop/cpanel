
package Whostmgr::XMLUI::NVData;

use strict;

use Whostmgr::NVData     ();
use Whostmgr::ApiHandler ();

sub nvget {
    my ( $key, $stor ) = @_;
    my $value = Whostmgr::NVData::get( substr( $key, 0, 128 ), substr( $stor, 0, 128 ) );

    return Whostmgr::ApiHandler::out( { 'value' => $value }, RootName => 'nvget', NoAttr => 1 );

}

sub nvset {
    my %OPTS = @_;
    my %NVData;
    foreach my $opt ( keys %OPTS ) {
        if ( $opt =~ /^key(.*)/ ) {
            my $extra = $1;
            $NVData{ $OPTS{$opt} } = $OPTS{ 'value' . $extra };
        }
    }

    my @RSD;
    foreach my $key ( keys %NVData ) {
        my $status = Whostmgr::NVData::set( substr( $key, 0, 128 ), substr( $NVData{$key}, 0, 2048 ), $OPTS{'stor'} ? substr( $OPTS{'stor'}, 0, 128 ) : '' );
        push @RSD, { 'key' => substr( $key, 0, 128 ), 'status' => $status };
    }

    return Whostmgr::ApiHandler::out( { 'result' => \@RSD }, RootName => 'nvset', NoAttr => 1 );

}
1;
