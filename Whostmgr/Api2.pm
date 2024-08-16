package Whostmgr::Api2;

# cpanel - Whostmgr/Api2.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Api2::Filter   ();
use Cpanel::Api2::Paginate ();
use Cpanel::Api2::Sort     ();
use Cpanel::Api2::Columns  ();
use Cpanel::Encoder::Tiny  ();
use Whostmgr::ACLS         ();
use Cpanel::AccessIds      ();
use Cpanel::Encoder::URI   ();
use Cpanel::JSON           ();
use Cpanel::LoadModule     ();    # needed for loadmodule
use Cpanel::Logger         ();

my %VARIABLE_PREFIX_TYPES = (
    '&' => 1,    # HTML encode
    '^' => 2,    # URI encode
    '@' => 3,    # CSS encode
    '-' => 4,    # json encode
);

sub whApi2 {
    my $module  = shift;
    my $func    = shift;
    my $rcfg    = shift;
    my $printfs = shift;
    my $noprint = shift;
    my $wantret = shift;

    $noprint =~ s/\[/\</g;
    $noprint =~ s/\]/\>/g;

    my %CFG = %{$rcfg};

    delete $Cpanel::CPERROR{ lc($module) };

    cpexpand_firstpass( \$printfs );
    my @PARGS     = split( /\,/, $printfs );
    my $formatstr = shift(@PARGS);
    my @encoded_args;
    foreach my $arg (@PARGS) {
        my $first_char = substr( $arg, 0, 1 );
        my $type       = $VARIABLE_PREFIX_TYPES{$first_char} || 0;
        if ($type) {
            $arg =~ s/^.//;
        }
        push @encoded_args, [ $arg, $type ];
    }
    cpexpand( \$formatstr );

    Cpanel::LoadModule::loadmodule($module);
    my $apiref;
    eval '$apiref = ' . "Cpanel::${module}::api2('${func}');";
    if ( !defined($apiref) ) {
        Cpanel::Logger::cplog( "Api2: $func is missing from Cpanel::${module}'s api2 function", 'warn', __PACKAGE__, 1 );
    }
    elsif ( !exists $apiref->{'func'} ) {
        $apiref->{'func'} = 'api2_' . $func;
    }

    $apiref->{'engine'} ||= 'hasharray';

    my $dataref;
    if ( $$apiref{'engine'} eq 'hasharray' || substr( $$apiref{'engine'}, 0, 5 ) eq 'array' ) {
        my $run_api2_ref = sub {
            eval "[Cpanel::${module}::$$apiref{func}(\%CFG)];";
        };
        my $run_user = Whostmgr::ACLS::hasroot() ? 'root' : $ENV{'REMOTE_USER'};
        local $Cpanel::user = $run_user;
        if ( $run_user eq 'root' ) {
            $dataref = $run_api2_ref->();
        }
        else {
            $dataref = Cpanel::AccessIds::do_as_user( $run_user, $run_api2_ref );
        }
    }
    if ( ref ${$dataref}[0] eq 'ARRAY' ) {
        $dataref = ${$dataref}[0];
    }

    if ( !defined $dataref ) {
        Cpanel::Logger::cplog( "Unable to run [Cpanel::${module}::" . $$apiref{'func'} . "(\%CFG)]; $!", 'warn', __PACKAGE__, 1 );
    }

    if ( defined $rcfg->{'api2_filter'} ) {
        $dataref = Cpanel::Api2::Filter::apply( $rcfg, $dataref );
    }

    if ( defined $rcfg->{'api2_sort'} ) {
        $dataref = Cpanel::Api2::Sort::apply( $rcfg, $dataref );
    }

    if ( defined $rcfg->{'api2_column'} ) {
        $dataref = Cpanel::Api2::Columns::apply( $rcfg, $dataref );
    }

    my $begin_chop;
    my $end_chop;
    if ( defined $rcfg->{'api2_paginate'} ) {
        ( $begin_chop, $end_chop ) = Cpanel::Api2::Paginate::setup_pagination_vars( $rcfg, $dataref );
    }

    my @ParsedData;
    my @data;
    my $count = 0;
    foreach my $keyref (@$dataref) {
        $count++;
        if   ( $count % 2 == 0 ) { $keyref->{'*count'} = 'odd'; }
        else                     { $keyref->{'*count'} = 'even'; }
        my $thisline = $formatstr;
        my @thisargs = @encoded_args;
        while ( $thisline =~ /\%/ && @thisargs ) {
            my $var   = shift(@thisargs);
            my $value = $keyref->{ $var->[0] };
            if ( $var->[1] == 1 ) {
                $value = Cpanel::Encoder::Tiny::safe_html_encode_str($value);
            }
            elsif ( $var->[1] == 2 ) {
                $value = Cpanel::Encoder::URI::uri_encode_str($value);
            }
            elsif ( $var->[1] == 3 ) {
                $value = Cpanel::Encoder::Tiny::css_encode_str($value);
            }
            elsif ( $var->[1] == 4 ) {
                $value = Cpanel::JSON::Dump($value);
            }

            #expand %'s that are not in the format string so they are not consumed
            cpexpand_percent( \$value );
            $thisline =~ s/\%/$value/;
        }
        push @data, $thisline;
    }

    #covert the \{percent}'s back into %'s
    foreach my $line (@data) {
        cpexpand_lastpass( \$line );
        push @ParsedData, $line;
    }

    if ($wantret) {
        return \@ParsedData;
    }

    print join( '', @ParsedData );
    return 1;
}

sub cpexpand_percent {
    my $printfs = shift;
    $$printfs =~ s/\%/\\\{percent\}/g;
}

sub cpexpand_lastpass {
    my $printfs = shift;
    $$printfs =~ s/\\\{percent\}/\%/g;

}

sub cpexpand_firstpass {
    my $printfs = shift;
    $$printfs =~ s/\\\,/\^\^\^/g;
}

sub cpexpand {
    my $pr = shift;
    if ( $$pr =~ /[\{\[\]]/ ) {
        $$pr =~ s/\[\[/\(/g;
        $$pr =~ s/\]\]/\)/g;
        $$pr =~ s/\\\{leftparenthesis\}/\(/g;
        $$pr =~ s/\\\{rightparenthesis\}/\)/g;
        $$pr =~ tr/\[/\</;
        $$pr =~ tr/\]/\>/;
        $$pr =~ s/\\\{colon\}/:/g;
        $$pr =~ s/\\\{comma\}/,/g;
        $$pr =~ s/\\\{leftbracket\}/\[/g;
        $$pr =~ s/\\\{rightbracket\}/\]/g;
    }
}

1;
