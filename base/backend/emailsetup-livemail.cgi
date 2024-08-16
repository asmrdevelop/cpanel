#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - base/backend/emailsetup-livemail.cgi    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel                         ();
use Cpanel::Encoder::Tiny          ();
use Cpanel::Encoder::URI           ();
use Cpanel::Encoder::VBScript      ();
use Cpanel::Form                   ();
use Cpanel::Locale                 ();
use Cpanel::Logger                 ();
use Cpanel::Validate::Domain::Tiny ();

# inputs: acct 	   - a string value representing the email account name.
#         inc_host - a string value representing the mail server domain name for incoming mail.
#         out_host - a string value representing the mail server domain name for outgoing mail.
#		  type 	   - an optional string value that should be either 'pop', 'pop3', or 'imap', it will default to imap if something else is entered
#		  usessl   - an optional boolean value indicating whether to a secure connection.  A value of 0 means no SSL;
#					 while a value of 1 means to use SSL.  If it isn't entered this will default to 0.
#		  mailport - an optional integer value representing the port to use when connecting to the mail server.  If it isn't entered,
#					 this will default to the standard port for the connection type (pop or imap) and it's SSL status.
#		  smtpport - an optional integer value representing the port to use when connecting to the SMTP server.  If it isn't entered,
#		  			 this will default to the standard SMTP port depending on SSL status.
#		  archive  - an optional boolean value representing whether the account is an email archive account.

# Must come before locale handle.
Cpanel::initcp();

my (%FORM) = Cpanel::Form::parseform();
my $logger;
my $locale = Cpanel::Locale->get_handle();

my $account = $FORM{'acct'};

if ( !$account ) {
    $logger ||= Cpanel::Logger->new();
    $logger->warn('Invalid account name passed.');
    my $invalidAccountTitle = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('Invalid Account') );
    my $invalidAccountBody  = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('An invalid account name was passed.') );
    print "Content-type: text/html\r\n\r\n<html><head><title>$invalidAccountTitle</title></head><body>$invalidAccountBody</body></html>";
    exit;
}

my $inc_host = $FORM{'inc_host'};
if ( !$inc_host || !Cpanel::Validate::Domain::Tiny::validdomainname($inc_host) ) {
    $logger ||= Cpanel::Logger->new();
    $logger->warn('Invalid domain name passed.');
    my $invalidDomainTitle = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('Invalid Domain') );
    my $invalidDomainBody  = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('An invalid domain name was passed.') );
    print "Content-type: text/html\r\n\r\n<html><head><title>$invalidDomainTitle</title></head><body>$invalidDomainBody</body></html>";
    exit;
}

my $out_host = $FORM{'out_host'};
if ( !$out_host || !Cpanel::Validate::Domain::Tiny::validdomainname($out_host) ) {
    $logger ||= Cpanel::Logger->new();
    $logger->warn('Invalid domain name passed.');
    my $invalidDomainTitle = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('Invalid Domain') );
    my $invalidDomainBody  = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('An invalid domain name was passed.') );
    print "Content-type: text/html\r\n\r\n<html><head><title>$invalidDomainTitle</title></head><body>$invalidDomainBody</body></html>";
    exit;
}

my (
    $fileName,         $vbFileName, $programNotFoundError, $directoryNotFoundError, $smtpPort,       $popEnabled, $archiveSetup, $archiveBool,
    $secureConnection, $mailPort,   $closeText,            $fileNotFoundText,       $popEnabledBool, $sslEnabledText
);
$popEnabled             = ( exists $FORM{'type'} && defined $FORM{'type'} && ( $FORM{'type'} eq 'pop' || $FORM{'type'} eq 'pop3' ) );
$popEnabledBool         = $popEnabled              ? "True"                : "False";
$secureConnection       = exists $FORM{'usessl'}   ? int $FORM{'usessl'}   : 0;
$sslEnabledText         = $secureConnection        ? "True"                : "False";
$mailPort               = exists $FORM{'mailport'} ? int $FORM{'mailport'} : 0;
$smtpPort               = exists $FORM{'smtpport'} ? int $FORM{'smtpport'} : 0;
$archiveSetup           = exists $FORM{'archive'}  ? int $FORM{'archive'}  : 0;
$archiveBool            = $archiveSetup            ? "True"                : "False";
$programNotFoundError   = $locale->maketext('[asis,Windows Live Mail] may not be installed; the following file was not found:');
$directoryNotFoundError = $locale->maketext('[asis,Windows Live Mail] may not be installed; the following directory was not found:');
$closeText              = $locale->maketext('Please close [asis,Windows Live Mail] before continuing.');
$fileNotFoundText       = $locale->maketext('File not found.');

if ($secureConnection) {
    my $port = $popEnabled ? 995 : 993;
    $mailPort = $mailPort > 0 ? sprintf( "%08x", $mailPort ) : sprintf( "%08x", $port );
    $smtpPort = $smtpPort > 0 ? sprintf( "%08x", $smtpPort ) : sprintf( "%08x", 465 );

    # Since this is a filename, we want the domain at the beginning and the file extension at the end. Thus, we only localize the label in between:
    $fileName = "$inc_host " . ( $archiveSetup ? $locale->maketext('Secure Archive Email Setup') : $locale->maketext('Secure Email Setup') ) . '.vbs';
}
else {
    my $port = $popEnabled ? 110 : 143;
    $mailPort = $mailPort > 0 ? sprintf( "%08x", $mailPort ) : sprintf( "%08x", $port );
    $smtpPort = $smtpPort > 0 ? sprintf( "%08x", $smtpPort ) : sprintf( "%08x", 25 );

    # Since this is a filename, we want the domain at the beginning and the file extension at the end. Thus, we only localize the label in between:
    $fileName = "$inc_host " . ( $archiveSetup ? $locale->maketext('Archive Email Setup') : $locale->maketext('Email Setup') ) . '.vbs';
}

$account                = Cpanel::Encoder::VBScript::encode_vbscript_str($account);
$inc_host               = Cpanel::Encoder::VBScript::encode_vbscript_str($inc_host);
$out_host               = Cpanel::Encoder::VBScript::encode_vbscript_str($out_host);
$vbFileName             = Cpanel::Encoder::VBScript::encode_vbscript_str($fileName);
$fileName               = Cpanel::Encoder::URI::uri_encode_str($fileName);
$programNotFoundError   = Cpanel::Encoder::VBScript::encode_vbscript_str($programNotFoundError);
$directoryNotFoundError = Cpanel::Encoder::VBScript::encode_vbscript_str($directoryNotFoundError);
$closeText              = Cpanel::Encoder::VBScript::encode_vbscript_str($closeText);
$fileNotFoundText       = Cpanel::Encoder::VBScript::encode_vbscript_str($fileNotFoundText);
$secureConnection       = sprintf( "%08x", $secureConnection ? 1 : 0 );

if ( open( my $wdisk_fh, '<', '/usr/local/cpanel/base/backend/emailsetup-livemail.vbs' ) ) {
    print <<EOM;
Content-Type: application/download; name="$fileName";
Content-Disposition: attachment; filename="$fileName";

EOM
    while ( readline($wdisk_fh) ) {
        s/\%inc_host\%/$inc_host/g;
        s/\%out_host\%/$out_host/g;
        s/\%mailPort\%/$mailPort/g;
        s/\%popEnabled\%/$popEnabledBool/g;
        s/\%fileName\%/$vbFileName/g;
        s/\%programNotFoundText\%/$programNotFoundError/g;
        s/\%dirNotFoundText\%/$directoryNotFoundError/g;
        s/\%fileNotFoundText\%/$fileNotFoundText/g;
        s/\%account\%/$account/g;
        s/\%closeText\%/$closeText/g;
        s/\%secureConnection\%/$secureConnection/g;
        s/\%smtpPort\%/$smtpPort/g;
        s/\%archiveEnabled\%/$archiveBool/g;
        s/\n/\r\n/g;
        print;
    }
    close($wdisk_fh);
}
else {
    $logger ||= Cpanel::Logger->new();
    $logger->warn('Unable to locate /usr/local/cpanel/base/backend/emailsetup-livemail.vbs.');
    my $fileNotFoundTitle = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('Unable to Locate File') );
    my $fileNotFoundBody  = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('Unable to locate file.') );
    print "Content-type: text/html\r\n\r\n<html><head><title>$fileNotFoundTitle</title></head><body>$fileNotFoundBody</body></html>";
    exit;
}
