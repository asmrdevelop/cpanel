package Cpanel::iContact::Email;

# cpanel - Cpanel/iContact/Email.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::Debug           ();
use Cpanel::Autodie         ();
use Cpanel::SafeRun::Object ();
use Cpanel::Email::Object   ();

# we cannot use utf-8 charset for binaries by default
our $DEFAULT_CONTENT_TYPE = 'text/plain';

###########################################################################
#
# Method:
#   write_email_to_fh
#
# Description:
#    Write an email to a file handle
#
# Parameters:
#   0 : A file handle to write the email to
#   1 - ...: See Cpanel::Email::Object
#
sub write_email_to_fh {
    my ( $sendmail_fh, %OPTS ) = @_;

    convert_attach_files_to_attachments( \%OPTS );

    return Cpanel::Email::Object->new( \%OPTS )->print($sendmail_fh);
}

sub convert_attach_files_to_attachments {
    my ($email_args_hr) = @_;
    for my $file ( @{ $email_args_hr->{'attach_files'} } ) {
        if ( ref $file ) {
            push @{ $email_args_hr->{'attachments'} }, $file;
        }
        else {
            next unless defined $file && length($file);
            my @FP       = split( /\//, $file );
            my $filename = pop @FP;
            if ( $filename =~ /\.log$/ ) {
                $filename .= '.txt';    #blackberry compat
            }

            $email_args_hr->{'attachments'} ||= [];

            my $mimetype = _guess_binary_mime_type_from_filename($file);

            my $rfh;
            try {
                Cpanel::Autodie::open( $rfh, '<', $file );
            }
            catch {
                undef $rfh;
                Cpanel::Debug::log_warn("Failed to open “$file”: $_");
            };

            next if !$rfh;

            push @{ $email_args_hr->{'attachments'} },
              {
                name         => $filename,
                content      => $rfh,
                content_type => $mimetype,
              };
        }
    }

    return 1;
}

sub _guess_binary_mime_type_from_filename {
    my ($file) = @_;

    # It's rare that we send anything but tars and text.
    # It would be nice to import the MIME module here;
    # however, the overhead is not worth it.

    # -B is for ASCII or UTF-8 we cannot set it to UTF-8 or we will have some malformed characters
    return 'application/x-tar'        if $file =~ m/\.tar\.?(?:gz|bz2|Z)?$/i;
    return 'application/octet-stream' if -B $file;

    # the content might contains some invalid utf8 code
    # here the content is !-B => ASCII or UTF-8
    #   so the content can contains some invalid UTF-8 characters

    # we are using file to guess the correct mime type and charset

    my $mime;
    eval { $mime = Cpanel::SafeRun::Object->new_or_die( 'program' => '/usr/bin/file', 'args' => [ qw{ --brief --mime }, $file ] )->stdout; 1 }
      or Cpanel::Debug::log_warn("Failed to check mime type for file “$file”: $_");
    chomp($mime)                  if $mime;
    $mime = $DEFAULT_CONTENT_TYPE if !$mime;

    return $mime;
}

1;
