package Cpanel::OptimizeWS;

# cpanel - Cpanel/OptimizeWS.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic (RequireUseWarnings)

use Cpanel                               ();
use Cpanel::PwCache                      ();
use Cpanel::LoadModule                   ();
use Cpanel::HttpUtils::Htaccess          ();
use Cpanel::Validate::LineTerminatorFree ();
use Cpanel::Exception                    ();

use constant MIMELIST_DIRECTIVE => '    AddOutPutFilterByType DEFLATE ';

sub OptimizeWS_init { }

sub optimizews {
    return if ( $Cpanel::CPDATA{'DEMO'} || !Cpanel::hasfeature('optimizews') );

    my $deflate_selection = shift;
    my $deflate_mime_list = shift;

    my ( $success, $error_message ) = _configure_deflate( $deflate_selection, $deflate_mime_list );

    if ( !$success ) {
        $Cpanel::CPERROR{'optimizews'} .= $error_message . "\n";
    }

    # Call other Optimize Website functions here

    return;
}

sub loadoptimizesettings {
    return if !Cpanel::hasfeature('optimizews');

    _load_deflate_settings();
    _load_apache_version();

    # Call other Optimize Website functions here

    return;
}

sub _configure_deflate {    ## no critic ( ProhibitExcessComplexity )
    my $deflate_selection = shift || return ( 0, 'No deflate settings specified' );
    my $deflate_mime_list = shift || '';

    if ( $deflate_selection eq 'list' ) {
        if (   !$deflate_mime_list
            || ( length(MIMELIST_DIRECTIVE) + length($deflate_mime_list) + 1 ) > 8192
            || $deflate_mime_list =~ tr{'"()\\\{\}$}{} ) {
            return ( 0, "Supplied list of MIME types is invalid" );
        }
        Cpanel::Validate::LineTerminatorFree::validate_or_die($deflate_mime_list);
    }
    elsif ( $deflate_selection ne 'disabled' && $deflate_selection ne 'all' ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter must be one of the following: [join,~, ,_2]', [ 'deflate_selection', [ 'list', 'disabled', 'all' ] ] );

    }

    my $docroot        = $Cpanel::homedir || Cpanel::PwCache::gethomedir();
    my $htaccess_file  = $docroot . '/.htaccess';
    my $htaccess_trans = Cpanel::HttpUtils::Htaccess::open_htaccess_rw($docroot);

    my @original_htaccess = split( m<^>m, ${ $htaccess_trans->get_data() } );

    if (   ( $deflate_selection eq 'disabled' && !grep( /^\s*<ifmodule\s+mod_deflate\.c/i, @original_htaccess ) )
        || ( $deflate_selection eq 'all'  && grep( /^\s*SetOutputFilter\sDEFLATE/i,                                       @original_htaccess ) )
        || ( $deflate_selection eq 'list' && grep( /^\s*AddOutPutFilterByType\s+DEFLATE\s+\Q${deflate_mime_list}\E\s*$/i, @original_htaccess ) ) ) {
        $htaccess_trans->close_or_die();
        return 1;
    }

    my $written     = $deflate_selection eq 'disabled';
    my $in_ifmodule = 0;

    my @htaccess = ();
    foreach my $line (@original_htaccess) {
        if ($in_ifmodule) {
            if ( $line =~ /^\s*<ifmodule/i ) {
                $in_ifmodule++;
            }
            if ( $line =~ /^\s*<\/ifmodule>/i ) {
                $in_ifmodule--;
            }
            if ( $deflate_selection eq 'disabled' ) {
                next;
            }
            if ( !$written ) {
                if ( $deflate_selection eq 'all' ) {
                    push @htaccess, "    SetOutputFilter DEFLATE\n";
                }
                else {
                    push @htaccess, MIMELIST_DIRECTIVE . $deflate_mime_list . "\n";
                }
                $written = 1;
            }
            push @htaccess, $line if ( $line !~ /^\s*(?:SetOutputFilter|AddOutPutFilterByType)\s+DEFLATE/i );
        }
        else {
            if ( $line =~ /^\s*<ifmodule\s*mod_deflate\.c/i ) {
                $in_ifmodule = 1;
                push @htaccess, $line unless ( $deflate_selection eq 'disabled' );
                next;
            }
            push @htaccess, $line;
        }
    }

    # If the htaccess file isn't blank, then check the last line of the file
    # and ensure that there is a new character present.
    $htaccess[-1] .= substr( $htaccess[-1], -1 ) eq "\n" ? "" : "\n" if scalar @htaccess;

    if ( !$written ) {
        push @htaccess, "<IfModule mod_deflate.c>\n";
        if ( $deflate_selection eq 'all' ) {
            push @htaccess, "    SetOutputFilter DEFLATE\n";
        }
        else {
            push @htaccess, MIMELIST_DIRECTIVE . $deflate_mime_list . "\n";
        }
        push @htaccess, <<'EO_DEFLATE';
    <IfModule mod_setenvif.c>
        # Netscape 4.x has some problems...
        BrowserMatch ^Mozilla/4 gzip-only-text/html

        # Netscape 4.06-4.08 have some more problems
        BrowserMatch ^Mozilla/4\.0[678] no-gzip

        # MSIE masquerades as Netscape, but it is fine
        # BrowserMatch \bMSIE !no-gzip !gzip-only-text/html

        # NOTE: Due to a bug in mod_setenvif up to Apache 2.0.48
        # the above regex won't work. You can use the following
        # workaround to get the desired effect:
        BrowserMatch \bMSI[E] !no-gzip !gzip-only-text/html

        # Don't compress images
        SetEnvIfNoCase Request_URI .(?:gif|jpe?g|png)$ no-gzip dont-vary
    </IfModule>

    <IfModule mod_headers.c>
        # Make sure proxies don't deliver the wrong content
        Header append Vary User-Agent env=!dont-vary
    </IfModule>
</IfModule>
EO_DEFLATE
    }

    $htaccess_trans->set_data( \join( '', @htaccess ) );
    my ( $status, $msg ) = Cpanel::HttpUtils::Htaccess::test_and_install_htaccess(
        'installdir'     => $docroot,
        'htaccess_trans' => $htaccess_trans,
    );

    return 1;
}

sub _load_deflate_settings {
    $ENV{'deflate_selected'}  = 'disabled';
    $ENV{'deflate_mime_list'} = 'text/html text/plain text/xml';

    my $htaccess_file = $Cpanel::homedir . '/.htaccess';

    my @htaccess = ();
    if ( -e $htaccess_file ) {
        open my $htaccess_fh, '<', $htaccess_file or return;
        @htaccess = <$htaccess_fh>;
        close $htaccess_fh;
    }
    else {
        return;
    }

    if ( !grep( /^\s*<ifmodule\s+mod_deflate\.c/i, @htaccess ) ) {
        return;
    }
    if ( grep( /^\s*SetOutputFilter\sDEFLATE/i, @htaccess ) ) {
        $ENV{'deflate_selected'} = 'all';
        return;
    }
    my $list_match = ( grep( /^\s*AddOutPutFilterByType\s+DEFLATE\s+/i, @htaccess ) )[0];
    if ($list_match) {
        $list_match =~ s/^\s*AddOutPutFilterByType\s+DEFLATE\s+//i;
        chomp $list_match;
        $ENV{'deflate_mime_list'} = $list_match;
        $ENV{'deflate_selected'}  = 'list';
        return;
    }
    return;
}

sub _load_apache_version {
    Cpanel::LoadModule::load_perl_module('Cpanel::ConfigFiles::Apache::modules');
    my $apv = Cpanel::ConfigFiles::Apache::modules::apache_long_version();
    if ( $apv =~ /^(\d\.\d)/ ) {
        $ENV{'optimize_apache_version'} = $1;
    }
    return;
}

1;
