#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - base/backend/ajax_maketext_syntax_util.pl
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use CGI                            ();
use Cpanel::JSON                   ();
use Cpanel::Locale                 ();
use MIME::Base64                   ();
use Cpanel::Locale::Utils::Custom  ();
use Cpanel::PwCache                ();
use Cpanel::SafeRun::Errors        ();
use Cpanel::StringFunc::SplitBreak ();
use Cpanel::Config::LoadCpUserFile ();
use Whostmgr::ACLS                 ();
no bytes;    # brings in bytes::functions && keeps bytes symantics as-is

_check_acls();
_check_application();

my $cgi         = CGI->new();
my $rendered    = '';
my $key         = $cgi->param('key');
my $charset     = $cgi->param('charset')    || 'utf-8';
my $locale_tag  = $cgi->param('locale_tag') || '';
my $from_locale = 0;

# Disable cpsrvd's cpanel-mode flag to prevent Cpanel::Locale::get_handle from panicking
local $ENV{'CPANEL'};

if ( !defined $cgi->param('key') || $cgi->param('key') =~ m/^\s*$/ ) {
    $@ = "no key given";
}
else {
    my $lh = Cpanel::Locale->new;
    eval { $rendered = $lh->_compile($key); };

    if ( !$@ ) {
        if ( ref $rendered eq 'SCALAR' ) {
            $rendered = ${$rendered};
        }
        elsif ( ref $rendered eq 'CODE' ) {
            my @args = $cgi->multi_param('args');

            eval { $rendered = $lh->$rendered(@args); };

            if ( !$@ && $locale_tag ) {
                $from_locale = $locale_tag;

                # only do this if it's a coderef:
                #    so the phrase is ok and we have a $locale_tag == render under locale to get it's nuances (e.g. think numf())
                $rendered = Cpanel::Locale->get_handle($locale_tag)->makevar( $key, @args );    # since this is coming from the lex we don't have to worry about it being marked in order to find it to put it into the lex
            }
        }
        else {
            $@ = "invalid response from compiler";                                              # this should never happen
        }
    }
}
my $error = '';
my $saved = 0;

if ($@) {
    $error = $@;
    $error =~ s{, as used .*}{}s;    # cleanup Locale::MakeText::_die_pointing()'s error message
}
else {
    if ( $cgi->param('save') ) {
        my $orig_key = $cgi->param('orig_key') || '';
        my $theme    = $cgi->param('theme')    || '';

        if ( !$orig_key || !$locale_tag || !$theme ) {
            $error = 'not enough data sent in order to save';
        }
        else {
            $theme = '' if $theme eq '/';
            my $extra = '';
            if ( $> == 0 ) {
                $saved = 1 if Cpanel::Locale::Utils::Custom::update_key( $orig_key, $key, $locale_tag, $theme, 1 );
            }
            else {
                my $user           = Cpanel::PwCache::getpwuid($>);
                my $new_value_safe = MIME::Base64::encode_base64( $key,      '' );
                my $orig_key_safe  = MIME::Base64::encode_base64( $orig_key, '' );
                if ( !$new_value_safe ) {
                    $extra = 'Could not save the new value, it was corrupted in passing.';    # We should never get here but just in case
                }
                else {
                    my @new_value_safe = Cpanel::StringFunc::SplitBreak::_word_split( $new_value_safe, 256 );
                    $extra = Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/bin/langwrap', 'SAVEKEY', $locale_tag, $theme, $orig_key_safe, @new_value_safe );
                    $saved = 1 if $? == 0;
                }
            }
            if ( !$saved ) {
                $error = 'Could not save key: ' . $extra;
            }
        }
    }
}

my $json = Cpanel::JSON::Dump(
    {
        'status'      => $error ? 0      : 1,
        'text'        => $error ? $error : $rendered,
        'saved'       => $saved,
        'from_locale' => $from_locale,
    }
);

print $cgi->header( '-type' => 'text/plain', '-charset' => $charset, '-Content_length' => bytes::length($json) );
print $json;

sub _check_acls {
    if ( $> == 0 ) {
        Whostmgr::ACLS::init_acls();

        if ( !Whostmgr::ACLS::checkacl('locale-edit') ) {
            _denied('Permission denied');
        }
    }
    else {
        if ( Cpanel::Config::LoadCpUserFile::loadcpuserfile( $ENV{'REMOTE_USER'} )->{'DEMO'} ) {
            _denied("Access Denied: $ENV{REMOTE_USER} is a demo account.");
        }
    }

    return;
}

sub _check_application {
    if ( $ENV{'WEBMAIL'} ) {
        warn "$ENV{REMOTE_ADDR} $ENV{REMOTE_USER} running $0 under webmail (denied)\n";
        _denied('Wrong application');
    }
    return;
}

sub _denied {
    my $msg = shift;
    print "Status: 403\r\nContent-type: text/plain\r\n\r\n";
    print Cpanel::JSON::Dump( { 'status' => 0, 'text' => $msg } );
    exit();
}
