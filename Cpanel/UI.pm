package Cpanel::UI;

# cpanel - Cpanel/UI.pm                            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

## uAPI note: per email w/Nick (2011-06-15), this module is dead-ish; neither
##   convert the subs below, nor bother to change existing API calls, such as
##   <cpanel UI="showresult(addmime)">. In fact, best to remove these tags
##   during the conversion to Template Toolkit.

use strict;
use Cpanel::Encoder::Tiny ();
use Cpanel::Encoder::URI  ();
use Cpanel::Math          ();
use Cpanel::SafeDir       ();

use vars qw(@ISA @EXPORT $VERSION);

require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw(UI_redirect UI_init UI_feedback UI_confirm UI_showresult UI_finishaction);

$VERSION = '1.0';

sub UI_init { }

sub _toHumanSize {
    goto &Cpanel::Math::_toHumanSize;
}

## see the ftp interface logout confirm page for Template Toolkit equivalent
sub UI_confirm {
    my %CFG = @_;
    if ( $CFG{'UI::confirm::version'} eq '' ) {
        print "Sorry, you must set the UI::confim::version setting!\n";
        return '';
    }

    foreach my $element ( keys %Cpanel::FORM ) {
        my $html_element = Cpanel::Encoder::Tiny::safe_html_encode_str($element);
        my $value        = $Cpanel::FORM{$element};
        print qq{<input type="hidden" name="$html_element" value="$value">\n};
    }
    return '';
}

## the very few existing calls of this do not have corresponding calls to UI_finishaction, which
##   is a dependent for this working
sub UI_showresult {
    my $resultkey = shift;
    return if ( $resultkey ne $Cpanel::FORM{'resultkey'} );
    my $result = $Cpanel::FORM{'result'};
    cssclean( \$result );
    if ( $Cpanel::FORM{'error'} eq '1' ) {
        print "<div class=\"errors\">";
    }
    else {
        print "<div class=\"result\">";
    }

    print $result;
    print "</div>";
}

sub UI_redirect {
    my $url = $Cpanel::FORM{'url'};
    cssclean( \$url );
    print "<meta http-equiv=\"refresh\" content=\"0;url=${url}\">";
    return;
}

sub UI_feedback {
    my $type = shift;
    my $opt  = shift;
    cssclean( \$opt );
    if ( $Cpanel::CPERROR{$type} ne '' ) {
        print "<div class=\"errors\">" . $Cpanel::CPERROR{$type};
    }
    else {
        print "<div class=\"result\">" . $opt;
    }

    print "</div>";
}

## no known calls; dead-ish, see UI_showresult
sub UI_finishaction {
    my ( $type, $resultkey, $url, $oktxt, %VARS ) = @_;
    my $r;
    my $errstr;
    if ( $Cpanel::CPERROR{$type} eq '' ) {
        $r = Cpanel::Encoder::Tiny::safe_html_encode_str($oktxt);
    }
    else {
        $r      = $Cpanel::CPERROR{$type};
        $errstr = '&error=1';
    }
    $r = Cpanel::Encoder::URI::uri_encode_str($r);
    $r =~ s/\+/\%2B/g;
    print "<meta http-equiv=\"refresh\" content=\"0;url=${url}?resultkey=$resultkey&";
    foreach my $var ( keys %VARS ) {
        print Cpanel::Encoder::URI::uri_encode_str($var) . '=' . Cpanel::Encoder::URI::uri_encode_str( $VARS{$var} ) . '&';
    }
    print "result=${r}${errstr}\">";

}

sub api2_listform {
    my %CFG = @_;

    my @RSD;
    foreach my $element ( keys %Cpanel::FORM ) {
        if ( $CFG{'match'} ne '' && $element !~ /$CFG{'match'}/ ) { next(); }
        my $value = $Cpanel::FORM{$element};
        if ( $CFG{'strip'} ne '' ) { $element =~ s/$CFG{'strip'}//g; }
        push( @RSD, { 'name' => $element, 'value' => $value } );
    }
    return (@RSD);
}

sub api2_dynamicincludelist {
    my %OPTS = @_;

    return _includelist( %OPTS, is_dynamic => 1 );
}

sub api2_includelist {
    my %OPTS = @_;

    return _includelist( %OPTS, is_dynamic => 0 );
}

sub _includelist {
    my %OPTS = @_;

    my $ilist      = $OPTS{'arglist'}   || '';
    my $nvilist    = $OPTS{'nvarglist'} || '';
    my $basedir    = $OPTS{'basedir'};       # unsafe
    my $is_dynamic = $OPTS{'is_dynamic'};    # not from browser

    my @IL = map { s/\0//g; s/\.\.//g; $_ } split( /\|/, $nvilist ne '' ? $nvilist : $ilist );

    # safe basedir
    my $filebase = Cpanel::SafeDir::safedir( $basedir, undef, $Cpanel::root . '/base/frontend/' . $Cpanel::CPDATA{'RS'} );

    if ($is_dynamic) {
        opendir( my $fl, $filebase );
        foreach my $fn ( sort readdir($fl) ) {
            next if ( $fn =~ /^\./ );
            my $testname = $fn;
            $testname =~ s/\.html$//g;
            push @IL, $testname if !grep { $_ eq $testname } @IL;
        }
        closedir($fl);
    }
    my @RSD;
    foreach my $ifile (@IL) {
        my $mfile = $filebase . '/' . $ifile . '.html';
        if ( open( my $aig, '<', $mfile ) ) {
            push( @RSD, { 'cell' => $ifile } );
            if ( $filebase ne "/usr/local/cpanel/base/frontend/paper_lantern" || $ifile ne "index" ) {
                main::cpanel_parse($aig);
            }
            close($aig);
        }
    }

    return @RSD;
}

# DEPRICATED
# Use:
#  <?cptt /usr/local/cpanel/base/shared/templates/paginate.tmpl ?> or
#  [% PROCESS '/usr/local/cpanel/base/shared/templates/paginate.tmpl' %]
sub api2_paginate_list {
    my %OPTS         = @_;
    my $itemsperpage = int $OPTS{'itemsperpage'} || int $OPTS{'api2_paginate_size'};
    my @itemlist     = sort { $a <=> $b } split( /\:/, $OPTS{'itemlist'} );
    my @RSD;
    foreach my $item (@itemlist) {
        push @RSD, { 'item' => $item, 'selected' => ( $itemsperpage eq $item ? 1 : 0 ) };
    }
    return \@RSD;
}

# DEPRICATED
# Use:
#  <?cptt /usr/local/cpanel/base/shared/templates/paginate.tmpl ?> or
#  [% PROCESS '/usr/local/cpanel/base/shared/templates/paginate.tmpl' %]
sub api2_paginate {
    my %OPTS         = @_;
    my $currentpage  = int $OPTS{'currentpage'};
    my $pages        = int $OPTS{'pages'};
    my $itemsperpage = int $OPTS{'itemsperpage'};
    my $url          = $OPTS{'url'};

    my $prevpage = $currentpage - 1;
    my $nextpage = $currentpage + 1;
    my $prevskip = $prevpage - 1;
    my $nextskip = $nextpage - 1;

    my $prevpage_api2_paginate_start = ( ( $prevpage - 1 ) * $itemsperpage ) + 1;
    my $nextpage_api2_paginate_start = ( ( $nextpage - 1 ) * $itemsperpage ) + 1;

    my $qs = join( '&', grep( !/^(skip|page|api2_paginate_start)=/, split( /\&/, $ENV{'QUERY_STRING'} ) ) );
    my $pg = qq{<style type="text/css">.UIpaginatoritem{float:left;margin: 0 5px 5px;padding: 0;text-align:center;font-size: 11px;}.UIpagination{margin: 0 auto;text-align:center;}.UIpaginator{margin: 0 auto;text-align:center;}</style>};
    if ( $OPTS{'nocss'} ) { $pg = ''; }
    $pg .= qq{<table class="UIpagination" border="0" align="center" id="pagination"><tr><td>&nbsp;</td><td>};
    if ( $prevpage > 0 ) { $pg .= qq{<div class="UIpaginatoritem"><a href="$url?api2_paginate_start=$prevpage_api2_paginate_start&page=$prevpage&skip=$prevskip&$qs">&lt;&lt;</a></div>}; }
    if ( $pages > 1 ) {
        $pg .= qq{<div class="UIpaginatoritem">[</div>};
        for ( my $i = 1; $i <= $pages; $i++ ) {
            my $iminusone           = $i - 1;
            my $api2_paginate_start = ( $iminusone * $itemsperpage ) + 1;
            $pg .= qq{<div class="UIpaginatoritem">};
            if ( $i == $currentpage ) {
                $pg .= qq{<b>$i</b>};
            }
            else {
                $pg .= qq{<a href="$url?api2_paginate_start=$api2_paginate_start&page=$i&skip=$iminusone&$qs">$i</a>};
            }
            $pg .= qq{</div>};
        }
        $pg .= qq{<div class="UIpaginatoritem">]</div>};
    }
    if ( $nextpage <= $pages ) { $pg .= qq{<div class="UIpaginatoritem"><a href="$url?api2_paginate_start=$nextpage_api2_paginate_start&page=$nextpage&skip=$nextskip&$qs">&gt;&gt;</a></div>}; }
    $pg .= qq{</td><td>&nbsp;</td></tr></table>};

    return [ { 'paginator' => $pg } ];
}

my $allow_demo         = { allow_demo => 1 };
my $allow_demo_csssafe = { allow_demo => 1, css_safe => 1 };

our %API = (
    listform           => $allow_demo,
    dynamicincludelist => $allow_demo,
    includelist        => $allow_demo,
    paginate           => $allow_demo_csssafe,
    paginate_list      => $allow_demo_csssafe,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

sub cssclean {
    require Cpanel::Encoder::Tiny;
    goto &Cpanel::Encoder::Tiny::angle_bracket_encode;
}

1;
