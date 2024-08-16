package Cpanel::Email::Mailbox;

# cpanel - Cpanel/Email/Mailbox.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

=pod

=head1 NAME

Cpanel::Email::Mailbox

=head1 DESCRIPTION

A utility module for detecting the format
of a mailbox in a given directory.

=head1 WARNINGS

The detection is intented to be lightweight and does not verify that the
mailbox is complete or that the mailbox is readable.  It is the callers
responsibility to ensure that the directory this module is operating on
can be read by the EUID that this module is running with if required.

=head1 SYNOPSIS

  my $format = Cpanel::Email::Mailbox::detect_format("$homedir/mail");

  if ( Cpanel::Email::Mailbox::looks_like_mdbox("$homedir/mail") ) {
    # do something to verify this really mdbox
    #
  }

  if (Cpanel::Email::Mailbox::looks_like_maildir("$homedir/mail") ) {
    # do something to verify this really maildir

  }

  ...

  Cpanel::Email::Mailbox::looks_like_mbox("$homedir/mail");

=cut

=head1 METHODS

=head2 detect_format

Detects the format of a mailbox in a given directory in
maildir, mdbox, or mdbox format.   If there are multiple
formats in the directory this function will return the first
format in can identify in the following order:

  maildir
  mdbox
  mbox

=head3 Arguments

A directory containing email in maildir, mdbox, or mbox format.

=head3 Return Value

The format that the mail directory appears to be in

=cut

sub detect_format {
    my ($maildir) = @_;

    if ( looks_like_maildir($maildir) ) {
        return 'maildir';
    }
    elsif ( looks_like_mdbox($maildir) ) {
        return 'mdbox';
    }
    elsif ( looks_like_mbox($maildir) ) {
        return 'mbox';
    }
    else {
        die "Could not detect the source_format of: $maildir";
    }

}

=head2 looks_like_mbox

Checks to see if the format of a mailbox in
a given directory appears to be mbox

=head3 Arguments

A directory that might contain email.

=head3 Return Value

0 - The directory does not contain an mbox mailbox
1 - The directory appears to contain an mbox mailbox

=cut

sub looks_like_mbox {
    my ($dir) = @_;

    return ( -e "$dir/inbox" ) ? 1 : 0;

}

=head2 looks_like_mdbox

Checks to see if the format of a mailbox in
a given directory appears to be mdbox

=head3 Arguments

A directory that might contain email.

=head3 Return Value

0 - The directory does not contain an mdbox mailbox
1 - The directory appears to contain an mdbox mailbox

=cut

sub looks_like_mdbox {
    my ($dir) = @_;

    return ( -d "$dir/storage" ) ? 1 : 0;

}

=head2 looks_like_maildir

Checks to see if the format of a mailbox in
a given directory appears to be maildir

=head3 Arguments

A directory that might contain email.

=head3 Return Value

0 - The directory does not contain a maildir mailbox
1 - The directory appears to contain a maildir mailbox

=cut

sub looks_like_maildir {
    my ($dir) = @_;

    return ( -d "$dir/cur" ) ? 1 : 0;

}

=head2 looks_like_format

Checks to see if the format of a mailbox in
a given directory appears to be a given format

=head3 Arguments

A directory that might contain email.

=head3 Return Value

0 - The directory does not contain a mailbox in the specified format
1 - The directory appears to contain a mailbox in the specified format

=cut

sub looks_like_format {
    my ( $dir, $format ) = @_;

    die "looks_like_format requires a maildir" if !$dir;
    die "looks_like_format requires a format"  if !$format;

    my $ref = __PACKAGE__->can( "looks_like_" . $format );

    die "looks_like_format requires one of the following formats: maildir, mdbox, or mbox" if !$ref;

    return $ref->($dir);
}

1;
