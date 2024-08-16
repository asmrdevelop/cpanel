package Cpanel::XMLForm;

# cpanel - Cpanel/XMLForm.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

sub makewellformedxml {
    my ($fh) = @_;
    my ($line);

    my @TAGLIST;
    my $xml;

    read( $fh, $line, 4194304 );
    while ( $line =~ /(\<[^\>\<]+\>*)/og ) {
        my $startpos = ( pos($line) - length($1) );
        if ( $startpos > 0 ) {
            $xml .= substr( $line, 0, $startpos );
        }
        my $tag = $1;
        $xml .= $tag;
        my $basetag = ( split( /\s+/, $tag ) )[0];
        $basetag = substr( $basetag, 1 );
        if ( substr( $basetag, -1, 1 ) eq '>' ) { $basetag = substr( $basetag, 0, length($basetag) - 1 ); }

        if ( substr( $basetag, 0, 1 ) eq '/' ) {
            if ( $TAGLIST[$#TAGLIST] eq substr( $basetag, 1 ) ) {
                pop(@TAGLIST);
            }
        }
        else {
            push( @TAGLIST, $basetag );
        }

        $line = substr( $line, pos($line) );
    }

    $xml .= $line;
    if ( $xml !~ /\>[\s\n\t]*/ ) {
        $xml =~ s/\<[^\<]+$//g;

        #strip out the half written tag
    }
    foreach my $tag ( reverse @TAGLIST ) {
        $xml .= "</${tag}>";
    }
    return $xml;
}

1;
