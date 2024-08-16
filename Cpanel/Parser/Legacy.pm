package Cpanel::Parser::Legacy;

# cpanel - Cpanel/Parser/Legacy.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- replocated from cpanel.pl and is not yet warnings safe

use Cpanel::JSON::Sanitize    ();
use Cpanel::Parser::Vars      ();
use Cpanel::Parser::FeatureIf ();
use Cpanel::Api2              ();
use Cpanel::Api2::Exec        ();
use Cpanel::AppSafe           ();
use Cpanel::Branding::Detect  ();
use Cpanel::Debug             ();
use Cpanel::Encoder::URI      ();
use Cpanel::ExpVar            ();
use Cpanel::JSON              ();
use Cpanel::StringFunc::Case  ();

my $cpanelaction = '';
my $inheaders;
my $tablecol;
my $tablecols;

=encoding utf-8

=head1 NAME

Cpanel::Parser::Legacy - Parser for legacy cPanel tags.

=head1 SYNOPSIS

    DO NOT USE THIS MODULE IN NEW CODE

=head1 DESCRIPTION

This is the parser for the legacy cPanel tags. DO NOT USE THIS MODULE IN NEW CODE

=cut

=head2 cpanel_parseblock

Entry point to parse legacy cpanel tags. DO NOT USE THIS MODULE IN NEW CODE

=cut

sub cpanel_parseblock {    ## no critic(Subroutines::RequireArgUnpacking Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my ( $stream, $hasaction, $data_before_tag ) = ( $_[0], 0 );

    #
    #        $logger->info("cpanel_parseblock: parsing[$stream]") if $Cpanel::CPVAR{'debug'} ;
    #
    # embtag explained
    # If we are not inside javascript and the tag does not contain a > then we are about to embed a tag
    #
    # If we are in embedded tag mode and we have a closing > outside a full tag ($data_before_tag) that we are going to print ( Cpanel::Parser::FeatureIf::on() ) without a < then we can close of the embtag
    #
    # Otherwise the value is retained
    #
    #
    if ($Cpanel::Parser::Vars::sent_headers) {
        if ( $Cpanel::Parser::Vars::incpanelaction || $stream =~ /\<cpanelaction/ ) {    # look ahead and do the smaller loop if we do not have a cpanelaction tag
            while ( $stream =~ m/(\<[^\>\<]+\>?)/ ) {
                if ( ( $Cpanel::Parser::Vars::current_tag = $1 ) && ( $data_before_tag = substr( substr( $stream, 0, $+[0], '' ), 0, -1 * length($Cpanel::Parser::Vars::current_tag) ) ) ) {
                    if ($Cpanel::Parser::Vars::incpanelaction) {
                        $hasaction = 1;
                        $cpanelaction .= $data_before_tag;
                    }
                    elsif ( Cpanel::Parser::FeatureIf::on() ) {
                        $Cpanel::Parser::Vars::buffer .= $data_before_tag;
                    }
                }
                _dotag(
                    (
                        $Cpanel::Parser::Vars::embtag =
                          ( !$Cpanel::Parser::Vars::javascript && $Cpanel::Parser::Vars::current_tag !~ tr/\!\>// && Cpanel::Parser::FeatureIf::on() ) ? 1
                        : (
                            ( $Cpanel::Parser::Vars::embtag && $data_before_tag && Cpanel::Parser::FeatureIf::on() && $data_before_tag !~ tr/<// && index( $data_before_tag, '>' ) > -1 ) ? 0
                            : $Cpanel::Parser::Vars::embtag
                        )
                    )
                );
            }
        }
        else {
            while ( $stream =~ m/(\<[^\>\<]+\>?)/ ) {
                $Cpanel::Parser::Vars::buffer .= $data_before_tag
                  if ( ( $Cpanel::Parser::Vars::current_tag = $1 )
                    && ( $data_before_tag = substr( substr( $stream, 0, $+[0], '' ), 0, -1 * length($Cpanel::Parser::Vars::current_tag) ) )
                    && Cpanel::Parser::FeatureIf::on() );
                _dotag(
                    $Cpanel::Parser::Vars::embtag =
                      ( !$Cpanel::Parser::Vars::javascript && $Cpanel::Parser::Vars::current_tag !~ tr/\!\>// && Cpanel::Parser::FeatureIf::on() ) ? 1
                    : (
                        ( $Cpanel::Parser::Vars::embtag && $data_before_tag && Cpanel::Parser::FeatureIf::on() && $data_before_tag !~ tr/<// && index( $data_before_tag, '>' ) > -1 ) ? 0
                        : $Cpanel::Parser::Vars::embtag
                    )
                );
            }
        }
    }
    else {
        while ( $stream =~ m/(\<[^\>\<]+\>?)/ ) {
            ## cpdev: cptt to UAPI path (does not do next conditional)
            if ( ( $Cpanel::Parser::Vars::current_tag = $1 ) && ( $data_before_tag = substr( substr( $stream, 0, $+[0], '' ), 0, -1 * length($Cpanel::Parser::Vars::current_tag) ) ) ) {
                if ($Cpanel::Parser::Vars::incpanelaction) {
                    $hasaction = 1;
                    $cpanelaction .= $data_before_tag;
                }
                elsif ( Cpanel::Parser::FeatureIf::on() ) {
                    if ($inheaders) {

                        # if we previously got a <cpanelheader tag then we can allow a \r\n as the next line might be one
                        # before we finish off the headers
                        if ( substr( $stream, pos($stream), 30 ) !~ /^[\r\n]+/ ) {
                            $data_before_tag =~ s/^[\r\n]+//;
                            $inheaders = 0;
                        }
                    }
                    if ( !$inheaders ) {
                        if ( !$Cpanel::Parser::Vars::sent_headers ) { cpanel::cpanel::finish_headers(); }
                        $Cpanel::Parser::Vars::buffer .= $data_before_tag;
                    }
                }
            }
            _dotag(
                (
                    $Cpanel::Parser::Vars::embtag =
                      ( !$Cpanel::Parser::Vars::javascript && $Cpanel::Parser::Vars::current_tag !~ tr/\!\>// && Cpanel::Parser::FeatureIf::on() ) ? 1
                    : (
                        ( $Cpanel::Parser::Vars::embtag && $data_before_tag && Cpanel::Parser::FeatureIf::on() && !$inheaders && $data_before_tag !~ tr/<// && index( $data_before_tag, '>' ) > -1 ) ? 0
                        : $Cpanel::Parser::Vars::embtag
                    )
                )
            );
        }
    }
    substr( $stream, 0, pos($stream), '' );
    if ($stream) {
        if ($Cpanel::Parser::Vars::incpanelaction) {
            $hasaction = 1;
            $cpanelaction .= $Cpanel::Parser::Vars::buffer . $stream;
        }
        elsif ( Cpanel::Parser::FeatureIf::on() ) {

            # see embtag explained
            $Cpanel::Parser::Vars::embtag = $Cpanel::Parser::Vars::embtag && $stream !~ tr/<// && index( $stream, '>' ) > -1 ? 0 : $Cpanel::Parser::Vars::embtag;
            print $Cpanel::Parser::Vars::buffer . $stream;
        }
    }
    else {
        print $Cpanel::Parser::Vars::buffer if length $Cpanel::Parser::Vars::buffer;
    }
    $Cpanel::Parser::Vars::buffer = '';
    return $hasaction;
}

sub _dotag_finished_headers {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix

    # first match must not match any of the tags in the end of this if/elsif/else block
    #
    # We short circuit tags that do not need processing
    #
    if ( !$Cpanel::Parser::Vars::incpanelaction && $Cpanel::Parser::Vars::current_tag !~ m{^</?(?:cp(?:anel|text)|\?(?:cp|xml)|t(?:extarea|itle)|s(?:tyle|cript)|endcpanelif|perl|body)}i ) {

        # Optimized with Regexp::Optimizer -- PREOPTIMIZED: /^<\/?(?:cpanel|endcpanelif|perl|\?cp|cptext|\?xml|textarea|title|style|script|body)/i
        return ( Cpanel::Parser::FeatureIf::on() ) ? ( $Cpanel::Parser::Vars::buffer .= $Cpanel::Parser::Vars::current_tag ) : ();
    }

    #
    # if and feature tags must come first as they control processing
    #
    elsif ( $Cpanel::Parser::Vars::current_tag =~ /^\<\/?(?:end)?cpanel(?:feature|if|else)/ ) {
        if ( $Cpanel::Parser::Vars::current_tag =~ /^\<cpanelfeature/ ) {
            return Cpanel::Parser::FeatureIf::execfeaturetag($Cpanel::Parser::Vars::current_tag) if !Cpanel::Parser::FeatureIf::get_nullfeatureif();
        }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^\<\/cpanelfeature/ ) {
            Cpanel::Parser::FeatureIf::set_nullfeatureif(0);
        }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^\<\/cpanelif/ || $Cpanel::Parser::Vars::current_tag =~ /^\<endcpanelif/ ) {
            Cpanel::Parser::FeatureIf::set_nullif(0);
        }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^\<cpanelelse/ ) {
            Cpanel::Parser::FeatureIf::set_nullif( Cpanel::Parser::FeatureIf::get_nullif() ? 0 : 1 );
        }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^\<cpanelif/ ) {
            return Cpanel::Parser::FeatureIf::execiftag($Cpanel::Parser::Vars::current_tag) if !Cpanel::Parser::FeatureIf::get_nullif();
        }
    }
    elsif ( Cpanel::Parser::FeatureIf::off() ) {

        # do nothing
    }

    # These are the most common tags we will process that have not been short circuited
    # above
    #
    # *** THE CONDITIONALS BELOW MUST FIRST CLEAR THE BUFFER ** with     print substr( $Cpanel::Parser::Vars::buffer, 0, length $Cpanel::Parser::Vars::buffer, '' )
    #
    elsif ( $Cpanel::Parser::Vars::current_tag =~ /^\<(?:perl|\?cp|\?cptt|cptext|cpanel|cpanelsaveinto)\b/ ) {
        print $Cpanel::Parser::Vars::buffer;
        $Cpanel::Parser::Vars::buffer = '';
        if ( $Cpanel::Parser::Vars::current_tag =~ /^\<cpanel\b/ ) {
            return cpanel::cpanel::exectag($Cpanel::Parser::Vars::current_tag);
        }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^\<\?cp\b/ ) {
            return cpexectag($Cpanel::Parser::Vars::current_tag);
        }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^<\?cptt\b/ ) {
            ## cpdev: cptt to UAPI path
            return cpanel::cpanel::cptt_exectag($Cpanel::Parser::Vars::current_tag);
        }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^\<cptext\b/ ) {

            # cptext arguments could conceivably need HTML in it (not the phrase, but the phrase arguments)
            # turning on uri decode (i.e., undef,undef,1) turns off expvar so check here and decode
            if ( $Cpanel::Parser::Vars::current_tag =~ tr/%// ) {
                $Cpanel::Parser::Vars::current_tag = Cpanel::Encoder::URI::uri_decode_str($Cpanel::Parser::Vars::current_tag);
            }
            return cpanel::cpanel::exectag( 'Locale="maketext(' . ( $Cpanel::Parser::Vars::current_tag =~ /^\<cptext\s+(.*)>/ )[0] . ')' );    ## no extract maketext
        }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^\<cpanelsaveinto\b/ ) {
            return execsaveintotag($Cpanel::Parser::Vars::current_tag);
        }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^\<perl\b/ ) {
            return perlexectag($Cpanel::Parser::Vars::current_tag);
        }
    }
    elsif ( $Cpanel::Parser::Vars::altmode || $Cpanel::Parser::Vars::incpanelaction || $Cpanel::Parser::Vars::current_tag =~ /^\<\/?cpanel(?:table|cell|action)/ ) {
        print $Cpanel::Parser::Vars::buffer;
        $Cpanel::Parser::Vars::buffer = '';
        if ( $Cpanel::Parser::Vars::can_leave_cpanelaction && $Cpanel::Parser::Vars::incpanelaction || $Cpanel::Parser::Vars::current_tag =~ /^\<\/?cpanelaction/ ) {
            if ( $Cpanel::Parser::Vars::current_tag =~ /^\<\/cpanelaction/ ) {
                $Cpanel::Carp::OUTPUT_FORMAT = ( $Cpanel::Parser::Vars::altmode ? 'xml' : 'html' );
                $cpanelaction .= $Cpanel::Parser::Vars::current_tag;
                cpanel::cpanel::docpanelaction($cpanelaction);
                $cpanelaction = '';
                if ( $Cpanel::CPVAR{'debug'} ) {
                    Cpanel::Debug::log_info("_dotag: Cpanel::Parser::incpanelaction=0");
                }
                $Cpanel::Parser::Vars::incpanelaction = 0;
            }
            elsif ( $Cpanel::Parser::Vars::current_tag =~ /^\<cpanelaction/ ) {
                if ( $Cpanel::CPVAR{'debug'} ) {
                    Cpanel::Debug::log_info("_dotag: Cpanel::Parser::incpanelaction=1");
                }
                $Cpanel::Carp::OUTPUT_FORMAT          = 'xml';
                $Cpanel::Parser::Vars::incpanelaction = 1;
                $cpanelaction .= $Cpanel::Parser::Vars::current_tag;
            }
            else {
                $cpanelaction .= $Cpanel::Parser::Vars::current_tag;
                return;
            }
        }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^\<\/?cpanel(?:table|cell)/ ) {
            if ( $Cpanel::Parser::Vars::current_tag =~ /^\<\/cpanelcell/ ) {
                print "</tr>" if ( $tablecol == 0 );
            }
            elsif ( $Cpanel::Parser::Vars::current_tag =~ /^\<cpanelcell/ ) {
                $tablecol++;
                $Cpanel::Parser::Vars::current_tag =~ /^\<cpanelcell([^\>]*)/;
                if ( $tablecol == 1 ) {
                    print "<tr${1}>";
                }
                if ( $tablecol == $tablecols ) {
                    $tablecol = 0;
                }
            }
            elsif ( $Cpanel::Parser::Vars::current_tag =~ /^\<\/cpaneltable/ ) {
                if ( $tablecol != 0 ) {
                    for ( my $i = ( $tablecol + 1 ); $i <= $tablecols; $i++ ) {
                        print "<td></td>";
                    }
                    print "</tr>";
                }
            }
            elsif ( $Cpanel::Parser::Vars::current_tag =~ /^\<cpaneltable/ ) {
                $Cpanel::Parser::Vars::current_tag =~ /^\<cpaneltable\s+(\d+)/;
                $tablecols = int($1);
                if ( $tablecols == 0 ) {
                    $tablecols = 5;
                }
                $tablecol = 0;
            }
        }
        elsif ($Cpanel::Parser::Vars::altmode) {

            #api1 is only wrapped in cpanelresult if xml
            print '{"apiversion":"1","type":"text","data":{"result":' . Cpanel::JSON::Dump( Cpanel::JSON::Sanitize::sanitize_for_dumping($Cpanel::Parser::Vars::current_tag) ) . '}}';
        }
    }
    elsif ( !( $Cpanel::Parser::Vars::live_socket_file && $Cpanel::Parser::Vars::current_tag =~ /^<\?xml/ ) ) {    # Do not send back <?xml from the client
        if    ( $Cpanel::Parser::Vars::current_tag =~ /^<textarea/i )   { $Cpanel::Parser::Vars::textarea = 1; }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^<\/textarea/i ) { $Cpanel::Parser::Vars::textarea = 0; }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^<title/i )      { $Cpanel::Parser::Vars::title    = 1; }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^<\/title/i )    { $Cpanel::Parser::Vars::title    = 0; }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^<style/i )      { $Cpanel::Parser::Vars::style    = 1; }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^<\/style/i )    { $Cpanel::Parser::Vars::style    = 0; }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^<script/i ) {

            #Only escape if this is really JavaScript.
            #This would match for text/plainjane as well as text/plain,
            #and text/html which should not be JavaScript. :)
            if ( $Cpanel::Parser::Vars::current_tag =~ m{type\s*=\s*['"]([^'"]+)}i ) {
                $Cpanel::Parser::Vars::javascript = ( $1 =~ m{javascript}i ) ? 1 : 0;
            }
            else {
                $Cpanel::Parser::Vars::javascript = 1;
            }
        }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^<\/script/i ) { $Cpanel::Parser::Vars::javascript = 0; }
        elsif ( $Cpanel::Parser::Vars::current_tag =~ /^<body/i ) {
            print $Cpanel::Parser::Vars::buffer ;
            $Cpanel::Parser::Vars::buffer = '';

            if ($Cpanel::Parser::Vars::trial_mode) {
                cpanel::cpanel::trial_html();
            }
            elsif ( $Cpanel::CONF{'disable-security-tokens'} ) {
                cpanel::cpanel::tokens_html();
            }
        }

        $Cpanel::Parser::Vars::buffer .= $Cpanel::Parser::Vars::current_tag;
    }
    return;
}

sub parse {
    my ( $inputfd, $livephp ) = @_;

    my $inputbuffer;
    while (1) {
        $inputbuffer = '';
        my $hastag  = 0;
        my $clength = int readline($inputfd) || last;
        read( $inputfd, $inputbuffer, $clength );
        if ( $Cpanel::CPVAR{'debug'} ) {
            Cpanel::Debug::log_info("Read request from php connector: [$inputbuffer]");
        }
        if    ( $inputbuffer =~ /\<cpanelxml\s*shutdown\=[\"\']+1/ ) { last; }
        elsif ( $inputbuffer =~ /\<cpaneljson\s*enable\=[\"\']+1/ ) {
            $Cpanel::Parser::Vars::jsonmode = 1;
            $Cpanel::Carp::OUTPUT_FORMAT    = 'suppress';

            #api1 is only wrapped in cpanelresult when xml
            print qq{<?xml version="1.0" ?>\n<cpanelresult>} . '{"data":{"result":"json"}}</cpanelresult>' . "\n";
            next;
        }

        #api1 is only wrapped in cpanelresult when xml
        print qq{<?xml version="1.0" ?>\n<cpanelresult>};

        if ( !_starts_with_cpanel_tag($inputbuffer) ) {
            if ($livephp) {
                print '{"apiversion":"1","error":"No Valid Command Given.","data":{"reason":"No Valid Command Given.","result":"0"},"type":"text"}</cpanelresult>' . "\n";
            }
            else {
                print qq{<apiversion>1</apiversion><type>text</type>} . qq{<data><result>0</result><reason>No Valid Command Given.</reason></data></cpanelresult>\n};
            }
        }

        $hastag = cpanel_parseblock($inputbuffer);

        if ($livephp) {
            print "</cpanelresult>\n";
        }
    }
    close($inputfd);
    return 1;
}

=head2 cpexectag

DO NOT USE THIS MODULE IN NEW CODE

 Perform parsing, execution, and printing of the <?cp func() ?> tag
 The supplied $task parameter should be the entire tag.
 The tag has the following format:
  <?cp mod::func(template,parm1,parm2) name=val name1=val1 ?>

  Where
       mod::func      specifies the func function in module mod
       template       is a string in a propietary template language with
                      replaceable parameters specified by '%'
       parm1,parm2    a list of named return values that specify what data is
                      inserted at each of the '%'
       name=val, ...  name/value pairs used as an input hash to the named
                      function

=cut

sub cpexectag {
    if ( !$Cpanel::Parser::Vars::loaded_api ) { cpanel::cpanel::load_api(); }
    no warnings;    ## no critic qw(TestingAndDebugging::ProhibitNoWarnings)
    *cpexectag = *_real_cpexectag;
    goto \&cpexectag;
}

sub _real_cpexectag {
    my $task = shift;

    $task =~ tr/\<\>//d;
    $task =~ s/^\?cp//;
    $task =~ s/\?$//;
    $task =~ s/^\s+//;
    $task =~ s/\s+$//;

    my ( %CFG, $name, $value, $command, $printfs, @PARGS, $formatstr, $noprint, $cfg, $rRET, $lastparn );
    if ( $task =~ /\|\|/ ) {
        ( $task, $noprint ) = split( /\s*\|\|\s*/, $task, 2 );

        # vars will be expanded, bracket notation happens before api2 modifies [ and ]
        if ( $noprint =~ m/maketext\(([^\)]*)\)/ ) {    ## no extract maketext

            # see embtag explained
            local $Cpanel::Parser::Vars::embtag = 1;    # TODO: a more sensible determination of the vars that dictate if Cpanel::Locale should do live edit JS or not
                                                        # since safesplit() gets $1 as an argument we have to copy it (via "$1" instead of $1) - Case 36254
            $noprint =~ s/maketext\(([^\)]*)\)/ ## no extract maketext
                my @args = Cpanel::StringFunc::SplitBreak::safesplit(',', "$1");
                foreach my $index (1..$#args) {
                    $args[$index] = Cpanel::ExpVar::expand_and_detaint( "$args[$index]",  \&Cpanel::Api2::escape_full);
                }
                cpanel::cpanel::_locale()->makevar(@args);
            /eg;
        }
    }

    $cfg = substr( $task, ( $lastparn = rindex( $task, ')' ) + 1 ) );
    $cfg =~ s/^\s+//;
    $cfg =~ s/\s+$//;

    ( $command, $printfs ) = split( /\(/, substr( $task, 0, $lastparn - 1 ), 2 );    #strip anything before the last par

    # vars will be expanded, bracket notation happens before api2 modifies [ and ]
    if ( $printfs =~ m/maketext\(([^\)]*)\)/ ) {                                     ## no extract maketext

        # see embtag explained
        local $Cpanel::Parser::Vars::embtag = 1;                                     # TODO: a more sensible determination of the vars that dictate if Cpanel::Locale should do live edit JS or not
                                                                                     # since safesplit() gets $1 as an argument we have to copy it (via "$1" instead of $1) - Case 36254
        $printfs =~ s/maketext\(([^\)]*)\)/ ## no extract maketext
            my @args = Cpanel::StringFunc::SplitBreak::safesplit(',', "$1");
            foreach my $index (1..$#args) {
                $args[$index] = Cpanel::ExpVar::expand_and_detaint( "$args[$index]",  \&Cpanel::Api2::escape_full);
            }
            my $res = cpanel::cpanel::_locale()->makevar(@args);
            $res =~ s{\,}{\\\{comma\}}g; $res =~ s{\:}{\\\{colon\}}g; # This masks out the untainted parts of the translation from needing api2 escaping
            $res;
        /eg;
    }

    # Special '\,' syntax. Thre are no instances where this is used in X3, but third party templates may still need it.
    $printfs =~ s/\\,/\\\{comma\}/g;

    ( $formatstr, @PARGS ) = split( /\s*\,\s*/, $printfs );

    Cpanel::Api2::cpexpand_firstpass( \$formatstr );
    Cpanel::Api2::cpexpand( \$formatstr );

    #
    # Magic to allow us to use ${group} instead of % in old api2 tags
    #
    my @CONVERTEDARGS;
    $formatstr =~ s/(%)|\$\{([^\}]+)\}/push(@CONVERTEDARGS,( $1 eq '%' ? (shift @PARGS) : $2));'%'/ge if ( $formatstr =~ m/\$\{/ );

    if ( exists $Cpanel::Parser::Vars::BACKCOMPAT{$command} ) {
        $command = $Cpanel::Parser::Vars::BACKCOMPAT{$command};
    }

    my ( $module, $func ) = split( /::/, $command );
    $module =~ tr/\r\n\t //d;
    $func   =~ tr/\r\n\t //d;

    # convered as part of BACKCOMPAT
    #if ( $module eq 'HttpUtils' ) { $module = 'UserHttpUtils'; }
    my $apiref = Cpanel::Api2::Exec::api2_preexec( $module, $func );

    if ( !$apiref ) {
        Cpanel::Debug::log_warn( $Cpanel::CPERROR{ Cpanel::StringFunc::Case::ToLower($module) } = "Execution of ${module}::${func} could not be completed because the function could not be resolved" );
        return;
    }

    if ( $Cpanel::appname eq 'webmail' && !Cpanel::AppSafe::checksafefunc( $module, $func, 2 ) ) {
        Cpanel::Debug::log_warn("Execution of ${module}::${func} is not permitted inside of webmail (api2)");
        $Cpanel::CPERROR{ Cpanel::StringFunc::Case::ToLower($module) } = "Execution of ${module}::${func} is not permitted inside of webmail (api2)";
        return;
    }

    my $modifier =
      defined $$apiref{'modify'}
      ? $$apiref{'modify'}
      : $Cpanel::IxHash::Modify;

    if ( $modifier eq 'none' && !$$apiref{'xss_checked'} ) {
        Cpanel::Debug::log_warn("Execution of ${module}::${func} is not permitted as Cpanel::IxHash::Modify is none and xss_checked is not set (api2)");
        return;
    }

    local $Cpanel::IxHash::Modify = $modifier;

    %CFG = map {
        ( $name, $value ) = ( split( /\s*\=/, $_, 2 ) );
        ( $name, $value =~ tr/\$/\$/ ? Cpanel::ExpVar::expvar( $value, 0, 1 ) : $value )
    } split( /\s*\,\s*/, $cfg );

    if ( $Cpanel::CPVAR{'debug'} ) {
        foreach my $key ( keys %CFG ) {
            Cpanel::Debug::log_info("api2: name=[$key],value=[$CFG{$key}]");
        }
    }

    ## cpdev: &api2_exec for <?cp> tags; note discards \%status
    my ($dataref) = Cpanel::Api2::Exec::api2_exec( $module, $func, $apiref, \%CFG );
    ## $dataref is more than likely an arrayOfHash

    $rRET = Cpanel::Api2::api2(
        'want'           => 'html',
        'cfg'            => \%CFG,
        'module'         => $module,
        'csssafe'        => ( $Cpanel::Parser::Vars::altmode ? 1 : $$apiref{'csssafe'} ),
        'engine'         => $$apiref{'engine'},
        'enginedata'     => $$apiref{'engineopts'},
        'args'           => [ $formatstr, ( @CONVERTEDARGS ? @CONVERTEDARGS : @PARGS ) ],
        'data'           => $dataref,
        'datapoints'     => $$apiref{'datapoints'},
        'dataregex'      => $$apiref{'datapointregexs'},
        'datapntaliases' => $$apiref{'datapointaliases'},
        'hacks'          => $$apiref{'hacks'},
        'noprint'        => $noprint,
    );
    if ( ref $rRET ne 'ARRAY' ) {
        Cpanel::Debug::log_warn("Non array returned from Api2::api2 module: $module - func: $func ($rRET)");
    }
    else {
        print @{$rRET};
    }
    return;
}

sub perlexectag {    ## no critic qw(Subroutines::RequireArgUnpacking)
    if ( $Cpanel::appname eq 'webmail' ) {
        Cpanel::Debug::log_warn("Execution of perl tags is not permitted inside of webmail");
        return;
    }
    if ($Cpanel::Parser::Vars::altmode) {

        #api1 is only wrapped in cpanelresult when xml
        print '{"apiversion":"1","type":"perl","data":{"result":';
    }

    my ($script) = $_[0];
    $script =~ s/^\<perl|\>$//g;
    $script =~ s/^\s*|\s*$//g;
    $script =~ s/^\n*|\n*$//g;
    if ( -e $script ) {
        require $script;
    }
    else {
        print '<b>[' . cpanel::cpanel::_locale()->maketext('A non-fatal error occurred during the execution of a cpanel tag.') . "]</b>\n";
    }
    if ($Cpanel::Parser::Vars::altmode) {
        print '}}';
    }
    return;
}

sub _execsaveintotag {
    my $saveintotag = shift;
    $saveintotag =~ s/^<cpanelsaveinto\s+//g;
    foreach my $tag ( split( /\s*\n\s* /, $saveintotag ) ) {
        ( my $variable, $Cpanel::Parser::Vars::cptag ) = split( /=/, $tag, 2 );
        $Cpanel::Parser::Vars::cptag =~ s/::/=/;
        cpanel::cpanel::exectag( $Cpanel::Parser::Vars::cptag, 0, $variable );
    }
    return;
}

sub _starts_with_cpanel_tag {
    return $_[0] =~ m/^<\/?(?:cpanel|endcpanelif|perl|\?cp|cptext)/i ? 1 : 0;
}

sub _dotag {
    Cpanel::Branding::Detect::autodetect_mobile_browser();

    #Header Check
    if ( $Cpanel::Parser::Vars::current_tag =~ /^\<cpanelheader/ ) {
        $Cpanel::Parser::Vars::current_tag =~ s/^\<cpanelheader\s*//;
        $Cpanel::Parser::Vars::current_tag =~ s/\>$//;
        my ( $header, $name ) = split( /=/, $Cpanel::Parser::Vars::current_tag, 2 );
        $header =~ s/^\"|\"$//;
        $name   =~ s/^\"|\"$// if index( $name, q{"} ) == 0;
        if ( Cpanel::StringFunc::Case::ToLower($header) eq 'content-type' ) {
            $Cpanel::Parser::Vars::sent_content_type = 1;
            $Cpanel::Parser::Vars::cptag             = 0;
        }
        $inheaders = 1;
        print $header . ':' . ' ' . $name . "\r\n";
        return;
    }
    elsif ( !$Cpanel::Parser::Vars::sent_headers ) {
        ## cpdev: cptt to UAPI path
        cpanel::cpanel::finish_headers();
    }
    goto &_dotag_finished_headers;
}

1;
