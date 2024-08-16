package Cpanel::Api2;

# cpanel - Cpanel/Api2.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

## no critic qw(TestingAndDebugging::RequireUseStrict)
use warnings;

use Cpanel::JSON          ();
use Cpanel::Debug         ();
use Cpanel::Encoder::Tiny ();
use Cpanel::ExpVar        ();
use Cpanel::Locale        ();

our $VERSION = '2.4';
my ( $locale, %DEEP_FORMAT_CODEREFS );

my ( %FULL_EXPANDERS, %FULL_ESCAPES, $FULL_ESCAPE_REGEX );

BEGIN {
    %FULL_EXPANDERS = (
        'leftparenthesis'   => '(',
        'rightparenthesis'  => ')',
        'colon'             => ':',
        'comma'             => ',',
        'leftbracket'       => '[',
        'rightbracket'      => ']',
        'leftcurlybrace'    => '{',
        'rightcurlybrace'   => '}',
        'percent'           => '%',
        'dollarsign'        => '$',
        'leftanglebracket'  => '<',    # Added to fix the broken cpexpand implemtation of expandiong '[[' to '('
        'rightanglebracket' => '>',    # Same as above for ']]'
    );

    %FULL_ESCAPES = reverse %FULL_EXPANDERS;

    # compile regexp
    my $re = '[' . join( '', map { '\\x' . unpack( 'H*', $_ ); } keys %FULL_ESCAPES ) . ']';
    $FULL_ESCAPE_REGEX = qr{$re};
}

my %CPEXPAND_PHASE_EXPANDERS = (
    %FULL_EXPANDERS,
    'leftcurlybrace' => '\\{leftcurlybrace}',    # delayed to lastpass phase since this is required to escape named placeholders
    'percent'        => '\\{percent}',           # delayed to lastpass phase since this is required to escape unnamed placeholders
    'dollarsign'     => '\\{dollarsign}',        # delayed to lastpass phase to protect against expvar expansions
);

#Note: At present there is no need to escape solely for the cpexpand phase without also escaping for the lastpass phase

my ( %LASTPASS_PHASE_EXPANDERS, $LASTPASS_EXPANDER_REGEX, %LASTPASS_ESCAPES, $LASTPASS_ESCAPE_REGEX );

BEGIN {
    %LASTPASS_PHASE_EXPANDERS = (
        'percent'        => '%',
        'leftcurlybrace' => '{',
        'dollarsign'     => '$',
    );
    $LASTPASS_EXPANDER_REGEX = '(' . join( '|', keys %LASTPASS_PHASE_EXPANDERS ) . ')';

    #Used to protect arbitrary input from interpolation as API2 placeholders through lastpass only
    %LASTPASS_ESCAPES = reverse %LASTPASS_PHASE_EXPANDERS;

    # compile regexp
    my $re = '[' . join( '', map { '\\x' . unpack( 'H*', $_ ); } keys %LASTPASS_ESCAPES ) . ']';
    $LASTPASS_ESCAPE_REGEX = qr{$re};
}

my %VARIABLE_PREFIX_TYPES = (
    '&' => 3,    # HTML encode
    '*' => 4,    # ??: not clear, but used as row flip-flop colorizer
    '^' => 5,    # URI encode
    '+' => 6,    # check="checked", based on boolean value
    '%' => 7,    # expvar
    '@' => 8,    # CSS encode
    '-' => 9,    # json encode
);

sub api2 {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my %ARGS = @_;

    ###
    ### Debug for Api2 => /usr/local/cpanel/logs/error_log
    ###
    my ( $want, $want_html, $want_hasharray, $engine, $enginedata, $csssafe, $rARGS, $rDATA, $rKEYS, $rCFG, $rDATAREGEX, $rDATAPNTALIASES, $hacks, $noprint, $module, $cfg_noexpvar, $useexpvar ) = (
        $ARGS{'want'},                                #want
        ( $ARGS{'want'} eq 'html'      ? 1 : 0 ),     #want_html
        ( $ARGS{'want'} eq 'hasharray' ? 1 : 0 ),     #want_hasharray
        $ARGS{'engine'},                              #engine
        $ARGS{'enginedata'},                          #enginedata
        $ARGS{'csssafe'},                             #csssafe
        $ARGS{'args'},                                #rARGS
        $ARGS{'data'},                                #rDATA
        $ARGS{'datapoints'},                          #rKEYS
        $ARGS{'cfg'},                                 #rCFG
        $ARGS{'dataregex'},                           #rDATAREGEX
        $ARGS{'datapntaliases'},                      #rDATAPNTALIASES
        $ARGS{'hacks'},                               #hacks
        $ARGS{'noprint'},                             #noprint
        $ARGS{'module'},                              #module
        ( $ARGS{'cfg'}->{'no_expvar'}   ? 1 : 0 ),    #cfg_noexpvar
        ( $ARGS{'args'}->[0] =~ tr/\$// ? 1 : 0 ),
    );

    my $formatstring = shift(@$rARGS);
    my ( %PROCESSED_ARGS, @PARSEDARGS, $arg, $type, $test_deepkey, $test_header, $expanded_test_deepformatstr, $test_deepformatstr, $test_footer );
    while ( $#$rARGS > -1 ) {
        $arg = shift(@$rARGS) || '';

        # Should not be done since we do this in cpanel.pl
        #$arg =~ s/^\s+//;
        #$arg =~ s/\s+$//;
        if ( exists $PROCESSED_ARGS{$arg} ) {
            push @PARSEDARGS, [ $PROCESSED_ARGS{$arg}, -10 ];
            next;
        }
        $PROCESSED_ARGS{$arg} = scalar @PARSEDARGS;

        if ( index( $arg, '?' ) > -1 && $arg =~ m/^\w+\=[^\?]+\?[^\:]+\:/ ) {
            $type = 1;
        }
        elsif ( index( $arg, ':' ) > -1 && ( ( $test_deepkey, $test_header, $test_deepformatstr, $test_footer ) = split( /:/, $arg, 4 ) ) && $test_deepkey && $test_deepformatstr ) {

            # Not needed done in cpanel.pl
            #$test_deepkey =~ s/^\s+//;
            $test_deepkey =~ s/\s+$//;    # REQUIRED
            if ( $test_header =~ tr/\{\[\]// ) { cpexpand( \$test_header ); }
            if ( $test_footer =~ tr/\{\[\]// ) { cpexpand( \$test_footer ); }

            # Here we take the deep format string which make look something like:
            # background-position:0 -${cssposition}px;width: ${width}px;height:${height}px;
            # and we safely escape it and convert it to a coderef that will take a hashref
            # of arguments and quickly insert them in the proper point

            # We build this all into a coderef called $deepformatcoderef
            # which can be called like
            # $deepformatcoderef->({'cssposition'=>'5','width'=>'5','height'=>4});
            #
            # This is a signficant speed up because we no longer have to parse the deepformatstring every loop
            # we can simply ship it off to the code ref to fill in the values
            #
            #usually needs to be expanded so no check
            cpexpand( \$test_deepformatstr );

            if ( $test_deepformatstr =~ /\$[^\{]/ ) {
                $test_deepformatstr = Cpanel::ExpVar::expand_and_detaint( $test_deepformatstr, \&escape_cpexpand_lastpass );
            }
            $test_deepformatstr =~ s/\\/\\\\/g;
            $test_deepformatstr =~ s/\'/\\\'/g;

            $expanded_test_deepformatstr = $test_deepformatstr;
            if ( !exists $DEEP_FORMAT_CODEREFS{$expanded_test_deepformatstr} ) {
                my ( $txt, $var, $code );
                while ( $test_deepformatstr =~ m/(\$\{[\*a-zA-Z0-9]+[^}]*\})/g ) {
                    $var = $1;
                    $txt = substr( $test_deepformatstr, 0, ( pos($test_deepformatstr) - length($var) ) );
                    $var =~ s/\$\{([\*a-zA-Z0-9]+)[^}]*\}/\$_[0]\-\>\{\'$1\'\}/;    #/g removed to prevent matching the same thing
                    $code .= q{'} . $txt . q{' . } . 'escape_cpexpand_lastpass(' . $var . ') . ';
                    substr( $test_deepformatstr, 0, pos($test_deepformatstr), '' );
                }
                eval '$DEEP_FORMAT_CODEREFS{ $expanded_test_deepformatstr } = sub {  return ' . ( $code .= q{ '} . $test_deepformatstr . q{'} ) . '; };';
                if ($@) {
                    die "Error while parsing api2 deepformat: $@\n";
                }
            }

            ( $type, $arg ) = ( 2, [ $test_deepkey, $test_header, $DEEP_FORMAT_CODEREFS{$expanded_test_deepformatstr}, $test_footer ] );
        }
        elsif ( $arg eq '*num' ) {    #*num is a special case
            $type = 0;
        }
        else {
            my $first_char = substr( $arg, 0, 1 );

            $type = $VARIABLE_PREFIX_TYPES{$first_char} || 0;
            if ($type) {
                $arg =~ s{^.}{};
                require Cpanel::URI::Escape::Fast if $type == 5;
            }
        }
        push @PARSEDARGS, [ $arg, $type ];
    }

    my ( $c, $begin_chop, $end_chop, @RET ) = (0);
    my $has_data = $Cpanel::CPVAR{'last_api2_has_data'} || ( scalar @$rDATA && defined $rDATA->[0] );

    if ( substr( $engine, 0, 5 ) eq 'array' && ref($rDATA) eq 'ARRAY' ) {
        if ( !$has_data ) {

            cleanup_noprint( \$noprint );
            cpexpand( \$noprint );
            $noprint = Cpanel::ExpVar::expand_and_detaint( $noprint, \&escape_cpexpand_lastpass );
            cpexpand_lastpass( \$noprint );

            # its either html or hasharray!
            return $want_html ? [$noprint] : { 'keys' => 0, 'noprint' => $noprint };
        }
        while ( my $datapoint = shift( @{$rDATA} ) ) {
            my %KEYVALUES;

            $KEYVALUES{'*num'} = ( ++$c % 2 == 0 ? 'odd' : 'even' );

            my $outputline = $formatstring;
            if ( $engine eq 'arraysplit' ) {
                my (@DAR) = split( /\Q${enginedata}\E/, $datapoint, scalar @$rKEYS );
                for ( my $i = 0; $i <= $#DAR; $i++ ) {
                    if ( ref( $${'rKEYS'}[$i] ) eq 'ARRAY' ) {
                        for ( my $j = 0; $j <= $#{ $${'rKEYS'}[$i] }; $j++ ) {
                            $KEYVALUES{ ${ $${'rKEYS'}[$i] }[$j] } = $DAR[$i];
                            if ( defined ${ $${'rDATAREGEX'}[$i] }[$j] && ${ $${'rDATAREGEX'}[$i] }[$j] ne '' ) {
                                eval '$KEYVALUES{${$${rKEYS}[$i]}[$j]} =~ ' . ${ $${'rDATAREGEX'}[$i] }[$j];
                            }
                        }
                    }
                    else {
                        $KEYVALUES{ $$rKEYS[$i] } = $DAR[$i];
                        if ( defined $$rDATAREGEX[$i] && $$rDATAREGEX[$i] ne '' ) {
                            eval '$KEYVALUES{$$rKEYS[$i]} =~ ' . $$rDATAREGEX[$i];
                        }
                    }
                }
            }
            elsif ( $engine eq 'array' ) {
                if ( ref( $${'rKEYS'}[0] ) eq 'ARRAY' ) {
                    for ( my $j = 0; $j <= $#{ $${'rKEYS'}[0] }; $j++ ) {
                        $KEYVALUES{ ${ $${'rKEYS'}[0] }[$j] } = $datapoint;
                        if ( defined ${ $${'rDATAREGEX'}[0] }[$j] && ${ $${'rDATAREGEX'}[0] }[$j] ne '' ) {
                            eval '$KEYVALUES{${$${rKEYS}[0]}[$j]} =~ ' . ${ $${'rDATAREGEX'}[0] }[$j];
                        }
                    }
                }
                else {
                    $KEYVALUES{ $$rKEYS[0] } = $datapoint;
                    if ( defined $$rDATAREGEX[0] && $$rDATAREGEX[0] ne '' ) {
                        eval '$KEYVALUES{$$rKEYS[0]} =~ ' . $$rDATAREGEX[0];
                    }
                }
            }
            if ( ref($rDATAPNTALIASES) ) {
                foreach my $alias ( keys %{$rDATAPNTALIASES} ) {
                    $KEYVALUES{$alias} = $KEYVALUES{ $$rDATAPNTALIASES{$alias} };
                }
            }

            if ($want_html) {
                foreach my $key ( keys %KEYVALUES ) {
                    if ( !$csssafe && $KEYVALUES{$key} =~ tr/\&\"\'\<\>// ) {

                        # This seems wrong since this code doesn't know the relevant escaping context of the output location
                        # Removing it will probably open XSS vulnerabilities where we now have over-escaping bugs though
                        $KEYVALUES{$key} = Cpanel::Encoder::Tiny::safe_html_encode_str( $KEYVALUES{$key} );
                    }
                }
                my $key;
                foreach my $arg (@PARSEDARGS) {
                    $key = $arg->[0];
                    my $url_encode;
                    if ( $key =~ m/^url:/ ) {
                        $key =~ s/^url://;
                        $url_encode = 1;
                    }

                    my $keyval = $arg->[1] == -10 ? $KEYVALUES{ $PARSEDARGS[0][0] } : $KEYVALUES{$key};

                    if ( $arg->[1] == 4 ) {    #* && !*num
                        $keyval =~ s/\\/\\\\/g;
                        $keyval =~ s/\"/\\\"/g;
                    }

                    $keyval = escape_cpexpand_lastpass($keyval);
                    $outputline =~ s{%}{$keyval};

                    if ($url_encode) {

                        # TODO: Remove in 11.50+
                        # Left in place for now to prevent ICBM launch sequences in third party code
                        $outputline .= 'blah';
                    }

                }

                # Expand the {percent} tags now that we are done.
                cpexpand_lastpass( \$outputline );
                push( @RET, $outputline );
            }
            elsif ($want_hasharray) {
                push( @RET, \%KEYVALUES );
            }
        }
    }
    elsif ( $engine eq 'hasharray' ) {
        $locale ||= Cpanel::Locale->get_handle();

        if ($useexpvar) {
            $formatstring = Cpanel::ExpVar::expand_and_detaint( $formatstring, \&escape_cpexpand_lastpass );
        }

        if ( !$has_data ) {
            cleanup_noprint( \$noprint );
            cpexpand( \$noprint );
            $noprint = Cpanel::ExpVar::expand_and_detaint( $noprint, \&escape_cpexpand_lastpass );
            cpexpand_lastpass( \$noprint );

            # its either html or hasharray!
            return $want_html ? [$noprint] : { 'keys' => 0, 'noprint' => $noprint };
        }
        my ( $outputline, $deepkey, $truekey, $keyval, $ol, $arg, $datahash, $deepformatcoderef, $header, $footer, $deepitem );
        if ($want_html) {
            while ( $datahash = shift( @{$rDATA} ) ) {
                $datahash->{'*num'} = ( ++$c % 2 == 0 ? 'odd' : 'even' );

                if ( ref($rDATAPNTALIASES) ) {
                    foreach my $alias ( keys %{$rDATAPNTALIASES} ) {
                        $datahash->{$alias} = $datahash->{ $rDATAPNTALIASES->{$alias} };
                    }
                }

                # @FORMATKEYS is used for holding all the variables which will be sent to sprintf
                my @FORMATKEYS;
                foreach $arg (@PARSEDARGS) {

                    #
                    # This if block is ordered by how likely the key type ($arg->[0]) is to come up
                    # 0, 2, 5, 3, 4, 1, 6, 7

                    if ( $arg->[1] == 0 ) {
                        $keyval = $datahash->{ $arg->[0] };
                        push @FORMATKEYS, ( !$csssafe && $keyval =~ tr/\&\"\'\<\>// ? escape_cpexpand_lastpass( Cpanel::Encoder::Tiny::safe_html_encode_str($keyval) ) : escape_cpexpand_lastpass($keyval) );
                    }
                    elsif ( $arg->[1] == 2 ) {    #multi level key
                        ( $deepitem, $ol, $deepkey, $header, $deepformatcoderef, $footer ) = ( 0, $arg->[0]->[1], @{ $arg->[0] } );
                        if ( ref $datahash->{$deepkey} ne 'ARRAY' ) {
                            push @FORMATKEYS, '';
                            next();
                        }
                        foreach my $dhash ( @{ $datahash->{$deepkey} } ) {
                            $dhash->{'*num'} = ( ++$deepitem % 2 == 0 ? 'odd' : 'even' );
                            $ol .= $deepformatcoderef->($dhash);
                        }
                        push @FORMATKEYS, $ol .= $footer;
                    }
                    elsif ( $arg->[1] == 9 ) {    #-
                        $keyval = $datahash->{ $arg->[0] };
                        push @FORMATKEYS, escape_cpexpand_lastpass( Cpanel::JSON::Dump($keyval) );
                    }
                    elsif ( $arg->[1] == 5 ) {    #^
                                                  # *** SPEED HACK *** for uri_escape
                        push @FORMATKEYS, escape_cpexpand_lastpass( Cpanel::URI::Escape::Fast::uri_escape( $datahash->{ $arg->[0] } ) );
                    }

                    elsif ( $arg->[1] == 3 ) {    #&
                        push @FORMATKEYS, escape_cpexpand_lastpass( Cpanel::Encoder::Tiny::safe_html_encode_str( $datahash->{ $arg->[0] } ) );
                    }
                    elsif ( $arg->[1] == 4 ) {    #* && !*num
                        $keyval = $datahash->{ $arg->[0] };
                        $keyval =~ s/\\/\\\\/g;
                        $keyval =~ s{/}{\\/}g;    #prevent </script> nastiness
                        push @FORMATKEYS, ( $keyval =~ s/\"/\\\"/g ? escape_cpexpand_lastpass($keyval) : escape_cpexpand_lastpass($keyval) );
                    }
                    elsif ( $arg->[1] == -10 ) {    # Test for a duplication of the same arg
                        push @FORMATKEYS, $FORMATKEYS[ $arg->[0] ];
                    }
                    elsif ( $arg->[1] == 1 ) {      # ternary test key
                        $arg->[0] =~ m/^(\w+)\=([^\?]+)\?([^\:]+)\:(.*)/;
                        $truekey = $1;
                        my $testval  = $2;
                        my $trueval  = $3;
                        my $falseval = $4;
                        chomp($falseval);
                        $keyval = $datahash->{$truekey};
                        cpexpand( \$testval );
                        $keyval = ( $testval eq $keyval ) ? $trueval : $falseval;
                        push @FORMATKEYS, $keyval;
                    }

                    elsif ( $arg->[1] == 6 ) {    #+
                                                  #test for checked
                        push @FORMATKEYS, ( $datahash->{ $arg->[0] } ? 'checked="checked"' : '' );
                    }
                    elsif ( $arg->[1] == 7 ) {    #%  This was previously an unsafe expvar expansion type.
                        Cpanel::Debug::log_warn("Unsupported API2 return prefix in: \%$arg->[0]");
                        $keyval = $datahash->{ $arg->[0] };
                        if ( !$csssafe && $keyval =~ tr/\&\"\'\<\>// ) {
                            $keyval = Cpanel::Encoder::Tiny::safe_html_encode_str($keyval);
                        }
                        $keyval =~ s/\%/\%25/;
                        push @FORMATKEYS, escape_cpexpand_lastpass($keyval);
                    }

                    elsif ( $arg->[1] == 8 ) {    #@
                        $keyval = $datahash->{ $arg->[0] };
                        push @FORMATKEYS, escape_cpexpand_lastpass( Cpanel::Encoder::Tiny::css_encode_str($keyval) );
                    }
                }
                my $i = 0;
                ( $outputline = $formatstring ) =~ s{%}{$FORMATKEYS[$i++]}g;

                # Expand the {percent} tags now that we are done.
                cpexpand_lastpass( \$outputline );

                push @RET, $outputline . '';
            }

        }
        elsif ($want_hasharray) {
            while ( $datahash = shift( @{$rDATA} ) ) {
                $datahash->{'*num'} = ( ++$c % 2 == 0 ? 'odd' : 'even' );
                if ( ref($rDATAPNTALIASES) ) {
                    foreach my $alias ( keys %{$rDATAPNTALIASES} ) {
                        $datahash->{$alias} = $datahash->{ $rDATAPNTALIASES->{$alias} };
                    }
                }
                push @RET, $datahash;
            }
        }

    }
    else {
        Cpanel::Debug::log_warn("Unsupported Datatype Passed to Api2: $engine");
    }
    if ( ref $hacks eq 'HASH' && $hacks->{$want} ) {
        eval $hacks->{$want};    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
    }

    # its either html or hasharray!
    return $want_html ? \@RET : { 'keys' => ( $#RET + 1 ), 'data' => \@RET };
}

# This is used only on the format string as an alternative escaping syntax for commas.
# It should not be used as an escaping syntax in new code since \{comma} is less ambiguous.
sub cpexpand_firstpass {
    ${ $_[0] } =~ s/\^\^\^/\,/g;
    return;
}

# This expander will expand all API2 escape sequences except for \{percent} and \{leftcurlybrace}
sub cpexpand {
    return if !defined ${ $_[0] };

    if ( ${ $_[0] } =~ tr/\[\]// ) {
        ${ $_[0] } =~ s/\[\[/\(/g;
        ${ $_[0] } =~ s/\]\]/\)/g;
        ${ $_[0] } =~ tr/\[\]/\<\>/;    ## no critic qw(Cpanel::TransliterationUsage)
    }

    # TODO: The buggy behaivor here of removing any \{something} sequences that don't map to an
    # expander has been preserved in v2.4 for backward compatibiltiy during the TSR release.
    # It should be switched at the next major release to only match available expanders.
    ${ $_[0] } =~ s/\\\{([^\}]+)}/$CPEXPAND_PHASE_EXPANDERS{$1}/g if ${ $_[0] } =~ tr/\\//;
    return;
}

# In the overall API2 pipeline, this function is called at the end to expand any API2-escaped % and { characters in the templates
sub cpexpand_lastpass {
    if ( defined ${ $_[0] } ) {
        ${ $_[0] } =~ s/\\\{($LASTPASS_EXPANDER_REGEX)\}/$LASTPASS_PHASE_EXPANDERS{$1}/go;
    }
    return;
}

# This will escape a string so that it will pass through both cpexpand and cpexpand_lastpass correctly.
# A string escaped in this fashion must run through BOTH expanders before it is returned to normal.
sub escape_full {
    return ( $_[0] =~ s/($FULL_ESCAPE_REGEX)/\\{$FULL_ESCAPES{$1}}/gor );
}

# This escapes a string so that it will pass through cpexpand_lastpass correctly.
# A string escaped in this fashion must NOT pass through cpexpand.
sub escape_cpexpand_lastpass {
    return ( $_[0] =~ s/($LASTPASS_ESCAPE_REGEX)/\\{$LASTPASS_ESCAPES{$1}}/gor );
}

sub cleanup_noprint {
    if ( defined ${ $_[0] } ) {
        ${ $_[0] } =~ s/^\s+//;
        ${ $_[0] } =~ s/\s+$//;
        ${ $_[0] } =~ s/^\'+//;
        ${ $_[0] } =~ s/\'+$//;
    }
    return 1;
}

1;
