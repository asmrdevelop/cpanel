package Cpanel::Branding::SpriteMap;

# cpanel - Cpanel/Branding/SpriteMap.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Debug ();

our %SPRITEMAPCACHE;

sub loadspritemap {
    my $spritefile = shift;
    return $SPRITEMAPCACHE{$spritefile} if defined $SPRITEMAPCACHE{$spritefile};

    if ( open( my $spfmap_fh, '<', "$spritefile.map" ) ) {
        my $mapversion = readline($spfmap_fh);
        while ( $mapversion =~ /^[\<\>]+\s+/ ) {
            $mapversion = readline($spfmap_fh);
        }
        chomp($mapversion);

        my $magicnum = readline($spfmap_fh);
        while ( $magicnum =~ /^[\<\>]+\s+/ ) {
            $magicnum = readline($spfmap_fh);
        }
        chomp($magicnum);

        my @IMGS;
        {
            local $/;

            # This code had to be commented below to prevent perltidy from making it all 1 line.
            # The fact this map is so complicated argues for a foreach loop.
            # TODO: This should be considered if this code is ever re-factored.
            @IMGS = map {    #
                (            #
                    m/[\<\>]+\s+/ ? ()    #
                    : (                   #
                        m/([^:]+):([^:]+):(\d+)x(\d+)/                                                             #
                        ?                                                                                          #
                          { 'img' => $1, 'cssposition' => $2, 'position' => $2, 'width' => $3, 'height' => $4 }    #
                        :                                                                                          #
                          ()                                                                                       #
                    )                                                                                              #
                )                                                                                                  #
            } split( /\n/, readline($spfmap_fh) );
        }

        close($spfmap_fh);

        return ( $SPRITEMAPCACHE{$spritefile} = { 'mapversion' => $mapversion, 'magicnum' => $magicnum, 'imgs' => \@IMGS } );
    }
    else {
        Cpanel::Debug::log_warn("Could not load sprite map file $spritefile.map: $!");
        return {};
    }

}
1;
