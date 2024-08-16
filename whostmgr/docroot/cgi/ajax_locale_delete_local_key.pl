#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/ajax_locale_delete_local_key.pl
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use CGI                           ();
use Cpanel::JSON                  ();
use Cpanel::Locale                ();
use Cpanel::Locale::Utils::Custom ();
use Whostmgr::ACLS                ();

no bytes;    # brings in bytes::functions && keeps bytes symantics as-is

_check_acls();

my $cgi    = CGI->new();
my $key    = $cgi->param('key');
my $theme  = $cgi->param('theme');
my $locale = $cgi->param('locale');

my $saved   = 0;
my $error   = 0;
my $value   = '';
my $charset = 'utf-8';

# TODO: better validation of 3 values below

if ( $key && $theme && $locale ) {

    $theme = '' if $theme eq '/';

    if ( Cpanel::Locale::Utils::Custom::del_key( $key, $locale, $theme, 1 ) ) {
        $saved = 1;

        system("/usr/local/cpanel/bin/build_locale_databases --clean --locale=$locale > /dev/null 2>&1");    # we don't use the task queue because we want this to complete before we continue instead of sometime in the future, that way the value returned is accurate

        local $Cpanel::CPDATA{'RS'} = $theme eq '/' ? '' : $theme;
        my $lh = Cpanel::Locale->get_handle($locale);
        $charset = $lh->encoding();
        {
            no warnings 'once';
            $value = ${ $lh->get_language_class() . '::Lexicon' }{$key} || $Cpanel::Locale::en::Lexicon{$key} || $key;    # compiled keys are not put back in CDB tied hash but kept in object;
        }
    }
    else {
        $error = "del_key() returned false";
    }
}

my $json = Cpanel::JSON::Dump(
    {
        'status' => $error ? 0      : 1,
        'text'   => $error ? $error : $value,
        'saved'  => $saved,
    }
);

print $cgi->header( '-type' => 'text/plain', '-charset' => $charset, '-Content_length' => bytes::length($json) );
print $json;

sub _check_acls {
    Whostmgr::ACLS::init_acls();

    if ( !Whostmgr::ACLS::checkacl('locale-edit') ) {
        print "Status: 401\r\nContent-type: text/plain\r\n\r\n";
        print Cpanel::JSON::Dump( { 'status' => 0, 'text' => "Permission denied" } );
        exit();
    }
}
