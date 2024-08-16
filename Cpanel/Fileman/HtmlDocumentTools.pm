package Cpanel::Fileman::HtmlDocumentTools;

# cpanel - Cpanel/Fileman/HtmlDocumentTools.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#-------------------------------------------------------------------------------------------------
# Purpose:  This module contains functions that work with html document content.
#-------------------------------------------------------------------------------------------------
# Developer Notes:
#
# The following links provide some supporting information:
#  * http://www.w3.org/International/questions/qa-html-encoding-declarations
#  * http://www.w3.org/International/questions/qa-htaccess-charset
#-------------------------------------------------------------------------------------------------
# TODO:
#-------------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------------
# Name:
#   update_html_document_encoding
# Desc:
#   Updates the embedded charset to the requested charset.
# Arguments:
#   content - string - Content to be updated in-place.
#   charset - string - Charset to mark in the document header. If charset not provided, will be
#   updated to utf-8.
# Returns:
#   string - the updated content.
#-------------------------------------------------------------------------------------------------
sub update_html_document_encoding {

    my ( $content, $charset ) = @_;

    # Sanitize the arguments. Assumes utf-8 unless specified otherwise.
    $charset ||= 'utf-8';
    if ($content) {

        # Remove any existing charset tags from the header.
        $content =~ s{<meta\s[^>]*?http-equiv[^>]+content-type[^>]+>}{}gi;    # Remove the <meta http-equiv content-type charset> from html5 and html4.01
        $content =~ s{<meta\s[^>]*?content-type[^>]+http-equiv[^>]+>}{}gi;    # Remove the <meta content-type charset http-equiv> from html5 and html4.01, since order doesn't matter for attributes
        $content =~ s{<meta\s[^>c]*?charset[^>]+>}{}gi;                       # Remove the <meta charset> tag from html5

        # Add the new pragma to the header, should be first in the list to meet the html5 first 1024 bytes rule.
        # We are using the pragma since it works for both html5 and html4.01
        $content =~ s{(<\s*head[^>]*>)}{$1<meta charset="$charset">};
    }

    return $content;
}

#-------------------------------------------------------------------------------------------------
# Name:
#   get_html_document_encoding
# Desc:
#   Gets the current charset setting from the document if provided.
# Arguments:
#   content - string - Content to analyze.
# Returns:
#   string - the content type if found
#-------------------------------------------------------------------------------------------------
sub get_html_document_encoding {
    my ($content) = @_;

    my ($content_type);
    if ( $content =~ /<meta\s[^>]+charset=([^>'"]+)[^>]+>/gi ) {
        $content_type = $1;
    }
    elsif ( $content =~ /<meta\s+charset=['"]([^>'"]+)[^>]+>/gi ) {
        $content_type = $1;
    }

    return $content_type;
}

1;
