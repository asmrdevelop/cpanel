package Cpanel::Email::Object;

# cpanel - Cpanel/Email/Object.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This module duplicates much of the logic in CPAN’s
# Email::MIME module. (Hopefully not too imperfectly.)
#
# What it gives is the ability to email via either a file handle or a blob.
# This is useful for when we don’t want to slurp the contents of the email.
#
# It knows how to create messages with:
#   - one text and/or one HTML body (use multipart/alternative if both)
#       The HTML body can have any number of “related” components.
#   - any number of (non-HTML-related) attachments
#   - any number of recipients
#   - an optional From: header
#   - an optional Subject: header
#----------------------------------------------------------------------

use strict;

use MIME::Base64      ();
use MIME::QuotedPrint ();

use Cpanel::Autodie       ();
use Cpanel::Hostname      ();
use Cpanel::FHUtils::Tiny ();
use Cpanel::LoadModule    ();
use Cpanel::UTF8::Strict  ();

my $CHUNK_SIZE = 2**14;

#NOTE: Per the previous logic from which this module was refactored
#(cf. Cpanel/iContact prior to 11.48), we must use this size for encode_base64.
#This will likely perform slowly when attaching large files.
my $CHUNK_SIZE_FOR_BASE64 = 60 * 57;

my $DEFAULT_CONTENT_TYPE = 'text/plain; charset="utf-8"';

#Opts are:
#   to              (array ref)
#   from            (optional, string)
#   subject         (optional, string)
#   text_body       (optional, scalar ref)
#   html_body       (optional, scalar ref)
#   html_related    (optional, arrayref)
#   attachments     (optional, arrayref)
#   x_headers       (optional, hashref)
#   headers         (optional, hashref)
#   message_id      (optional, string, without @hostname)
#   charset         (optional, string, charset for text_body and html_body,
#                    default UTF-8)
#
#One of "text_body" or "html_body" must be given.
#
#"attachments" and "html_related" are arrayrefs of hashrefs, each of which is:
#
#   {
#       content_type => (optional) default to $DEFAULT_CONTENT_TYPE
#                       NOTE: include charset if it’s important
#       content_id   => (optional)
#       name         => (optional; NOTE: Not safe for quotes!)
#       content      => (scalar ref or file handle)
#   }
#
#NOTE: Any file handles that are passed in here will NOT be "rewound".
#It is the caller's responsibility to do that, if such is desired!
#
sub new {    ## no critic(RequireArgUnpacking)
    my $class = shift;

    # For large emails we allow passing in a reference to avoid
    # the memory copy
    my $opts_ref;
    if ( ref $_[0] ) {
        $opts_ref = $_[0];
    }
    else {
        $opts_ref = {@_};
    }

    _validate_opts($opts_ref);
    _fill_in_message_id($opts_ref);

    for (qw( subject from )) {
        $opts_ref->{$_} //= q<>;
    }

    $opts_ref->{'charset'} //= 'utf-8';

    return bless { _opts => $opts_ref }, $class;
}

sub _print_mime_header_if_needed {
    my ( $self, $wfh ) = @_;

    if ( !$self->{'_mime_header_is_printed'} ) {
        Cpanel::Autodie::print( $wfh, "Mime-Version: 1.0\n" );
        $self->{'_mime_header_is_printed'} = 1;
    }

    return;
}

#NOTE: This print()s, which is buffered output. Don’t
#mix this with unbuffered output, or you will reap sadness and despair.
#
sub print {
    my ( $self, $wfh ) = @_;

    local $self->{'_mime_header_is_printed'} = 0;

    my %headers_to_encode = (
        To => join( ',', @{ $self->{'_opts'}{'to'} } ),
    );

    foreach my $param (qw{from Reply-To subject}) {
        next if !length $self->{'_opts'}{$param};
        $headers_to_encode{ ucfirst($param) } = $self->{'_opts'}{$param};
    }

    if ( $self->{'_opts'}{'x_headers'} ) {
        my $xh_hr = $self->{'_opts'}{'x_headers'};
        @headers_to_encode{ map { "X-$_" } keys %$xh_hr } = values %$xh_hr;
    }

    if ( $self->{'_opts'}{'headers'} ) {
        my $hhr = $self->{'_opts'}{'headers'};
        @headers_to_encode{ keys %$hhr } = values %$hhr;
    }

    if ( !exists $headers_to_encode{'Date'} ) {
        require Cpanel::Time::HTTP;
        $headers_to_encode{'Date'} = Cpanel::Time::HTTP::time2http();
    }

    my %encoded_headers;
    {
        local $@;

        eval {
            require    # Cpanel::Static OK - inside eval block
              Email::MIME::Encode;
            require Encode;

            my @keys_to_encode = keys %headers_to_encode;
            foreach my $key (@keys_to_encode) {
                my $value = $headers_to_encode{$key};

                # do not alter email addresses to preserve '<angle brackets>' if encoding is not needed
                #   Email::MIME::Encode >= 1.943 is using Email::Address::Signature::XS and will not preserve angle brackets.
                if ( defined $value && $key =~ qr{^(?: From | To | Bcc | Cc)$}xi ) {
                    if ( $value =~ qr{^[-_@+.a-zA-Z0-9<>, ]{5,79}$} ) {    # skip most of the encode when possible to preserve angle brackets
                        $encoded_headers{$key} = $value;
                        next;
                    }

                    require                                                # Cpanel::Static OK - inside eval block
                      Email::MIME::Header::AddressList;
                    my $decoded      = Encode::decode( $self->{'_opts'}{'charset'}, $value );
                    my $address_list = Email::MIME::Header::AddressList->from_string($decoded);
                    $encoded_headers{$key} = $address_list->as_mime_string();

                    next;
                }

                my $decoded = Encode::decode( $self->{'_opts'}{'charset'}, $value );
                $encoded_headers{$key} = Email::MIME::Encode::maybe_mime_encode_header( $key, $decoded, $self->{'_opts'}{'charset'} );
            }

        };

        # if we fail to load Email::MIME::Encode, like when running during 11.46 -> 11.48 upgrades,
        # we'll fall back to using a simpler fallback
        if ($@) {
            %encoded_headers = map { $_ => Cpanel::UTF8::Strict::decode( $headers_to_encode{$_} ) } keys %headers_to_encode;
        }
    }

    my @headers = map { "$_: $encoded_headers{$_}" } sort keys %encoded_headers;

    Cpanel::Autodie::print( $wfh, map { "$_\n" } @headers );

    my $has_attachments = $self->{'_opts'}{'attachments'};
    $has_attachments &&= @$has_attachments;

    if ($has_attachments) {
        my $boundary = $self->_make_boundary('mixed');
        $self->_print_mime_header_if_needed($wfh);
        Cpanel::Autodie::print( $wfh, qq<Content-Type: multipart/mixed; boundary="$boundary"\n\n> );

        Cpanel::Autodie::print( $wfh, "--$boundary\n" );
        $self->_print_full_body($wfh);

        for my $attch_hr ( @{ $self->{'_opts'}{'attachments'} } ) {
            $self->_print_attachment( $wfh, $boundary, $attch_hr );
        }

        Cpanel::Autodie::print( $wfh, "--$boundary--\n" );
    }
    else {
        $self->_print_full_body($wfh);
    }

    return;
}

sub _fill_in_message_id {
    my ($opts) = @_;
    return if exists $opts->{'headers'} && exists $opts->{'headers'}{'Message-Id'};
    my $left_part = $opts->{'message_id'} // do {
        require Cpanel::Rand::Get;
        time . "." . Cpanel::Rand::Get::getranddata(16);
    };
    my $hostname = Cpanel::Hostname::gethostname();
    $opts->{'headers'}{'Message-Id'} = "<$left_part\@$hostname>";
    return;
}

sub _print_attachment {
    my ( $self, $wfh, $boundary, $attch_hr ) = @_;

    Cpanel::Autodie::print( $wfh, "\n--$boundary\n" );

    my $content_type = $attch_hr->{'content_type'} || $DEFAULT_CONTENT_TYPE;
    my $type_header  = "Content-Type: $content_type; x-unix-mode=0600";

    my $disp_header = 'Content-Disposition: attachment';
    if ( length $attch_hr->{'name'} ) {

        #TODO: Toughen this to accept quotes, etc.
        my $mime_filename = qq["$attch_hr->{'name'}"];
        $disp_header .= "; filename=$mime_filename";
        $type_header .= "; name=$mime_filename";
    }

    Cpanel::Autodie::print( $wfh, "$type_header\n$disp_header\n" );

    if ( length $attch_hr->{'content_id'} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Encoder::URI');    #load_perl_module to keep upcp.static working on c6
        my $cid_uri = Cpanel::Encoder::URI::uri_encode_str( $attch_hr->{'content_id'} );
        Cpanel::Autodie::print( $wfh, "Content-ID: <$cid_uri>\n" );
    }

    Cpanel::Autodie::print( $wfh, "Content-Transfer-Encoding: base64\n\n" );

    #NOTE: See above about comment about $CHUNK_SIZE_FOR_BASE64 for background.
    if ( 'SCALAR' eq ref $attch_hr->{'content'} ) {
        my $content_sr = $attch_hr->{'content'};
        my $pos        = 0;
        while ( $pos < length $$content_sr ) {
            Cpanel::Autodie::print( $wfh, MIME::Base64::encode_base64( substr( $$content_sr, $pos, $CHUNK_SIZE_FOR_BASE64 ) ) );
            $pos += $CHUNK_SIZE_FOR_BASE64;
        }
    }
    elsif ( Cpanel::FHUtils::Tiny::is_a( $attch_hr->{'content'} ) ) {
        my $buffer;
        while ( Cpanel::Autodie::read( $attch_hr->{'content'}, $buffer, $CHUNK_SIZE_FOR_BASE64 ) ) {    #must be this size for encode_base64
            Cpanel::Autodie::print( $wfh, MIME::Base64::encode_base64($buffer) );
        }
    }

    return;
}

sub _print_body_part {
    my ( $self, $wfh, $body_key, $content_type ) = @_;

    my $body_sr = $self->{'_opts'}{$body_key};
    my $charset = $self->{'_opts'}{'charset'};

    Cpanel::Autodie::print( $wfh, "Content-Type: $content_type; charset=$charset\n" );
    Cpanel::Autodie::print( $wfh, "Content-Transfer-Encoding: quoted-printable\n\n" );
    $self->_send_msg_into_fh( $body_sr, $wfh );

    return;
}

sub _print_full_body {
    my ( $self, $wfh ) = @_;

    my $text_sr = $self->{'_opts'}{'text_body'};
    my $html_sr = $self->{'_opts'}{'html_body'};

    my $has_text = $text_sr && length $$text_sr;
    my $has_html = $html_sr && length $$html_sr;

    $self->_print_mime_header_if_needed($wfh);
    if ($has_text) {
        if ($has_html) {
            my $boundary = $self->_make_boundary('alternative');

            Cpanel::Autodie::print( $wfh, qq<Content-Type: multipart/alternative; boundary="$boundary"\n\n> );

            Cpanel::Autodie::print( $wfh, "--$boundary\n" );
            $self->_print_body_part( $wfh, 'text_body', 'text/plain' );

            Cpanel::Autodie::print( $wfh, "\n--$boundary\n" );

            $self->_print_html_section($wfh);

            Cpanel::Autodie::print( $wfh, "\n--$boundary--\n" );
        }
        else {
            $self->_print_body_part( $wfh, 'text_body', 'text/plain' );
        }
    }
    elsif ($has_html) {
        $self->_print_html_section($wfh);
    }
    else {
        die "No body to print!";    #should never get here, but just in case
    }

    return;
}

sub _print_html_section {
    my ( $self, $wfh ) = @_;

    my $html_sr = $self->{'_opts'}{'html_body'};

    my $html_rel = $self->{'_opts'}{'html_related'};
    $html_rel &&= @$html_rel;

    if ($html_rel) {
        my $boundary = $self->_make_boundary('related');

        $self->_print_mime_header_if_needed($wfh);
        Cpanel::Autodie::print( $wfh, qq<Content-Type: multipart/related; boundary="$boundary"\n\n> );

        Cpanel::Autodie::print( $wfh, "--$boundary\n" );
        $self->_print_body_part( $wfh, 'html_body', 'text/html' );

        for my $rel_part ( @{ $self->{'_opts'}{'html_related'} } ) {
            $self->_print_attachment( $wfh, $boundary, $rel_part );
        }

        Cpanel::Autodie::print( $wfh, "\n--$boundary--\n" );
    }
    else {
        $self->_print_body_part( $wfh, 'html_body', 'text/html' );
    }

    return;
}

#NOTE: Technically, this doesn't work unless we encode the message bodies
#such that they can never contain what would be in the boundary. We could
#accomplish that by QP- or base64-encoding the message bodies. It's unlikely
#ever to be a concern, though; someone would really have to *try* to make
#the return value of the following method appear within a message body.
#
sub _make_boundary {
    my ( $self, $base_str ) = @_;

    return join( '-', $base_str, __PACKAGE__, $$, time(), rand() );
}

sub _construct_content_type {
    my ($self) = @_;

    my $type = $self->{'_opts'}{'content_type'};
    if ( $self->{'_opts'}{'charset'} ) {
        $type .= "; charset=$self->{'_opts'}{'charset'}";
    }

    return $type;
}

sub _send_msg_into_fh {
    my ( $self, $msg_ref, $wfh ) = @_;

    if ( Cpanel::FHUtils::Tiny::is_a($msg_ref) ) {
        my $buffer;
        while ( Cpanel::Autodie::read( $msg_ref, $buffer, $CHUNK_SIZE ) ) {
            Cpanel::Autodie::print( $wfh, MIME::QuotedPrint::encode_qp($buffer) );
        }
    }
    else {
        Cpanel::Autodie::print( $wfh, MIME::QuotedPrint::encode_qp($$msg_ref) );
    }

    return;
}

#----------------------------------------------------------------------

#NOTE: Static (private) method
sub _validate_opts {
    my ($opts_hr) = @_;

    if ( ref( $opts_hr->{'to'} ) ne 'ARRAY' ) {
        die "“to” must be an arrayref, not “$opts_hr->{'to'}”!";
    }

    for (qw( text_body  html_body )) {
        next if !defined $opts_hr->{$_};
        next if ref( $opts_hr->{$_} ) eq 'SCALAR';
        next if Cpanel::FHUtils::Tiny::is_a( $opts_hr->{$_} );

        die "“$_” must be a file handle or a SCALAR reference, not “$opts_hr->{$_}”!";
    }

    if ( !grep { defined $opts_hr->{$_} } qw( text_body  html_body ) ) {
        die "Give either text or HTML!";
    }

    if ( defined $opts_hr->{'attachments'} ) {
        if ( ref( $opts_hr->{'attachments'} ) ne 'ARRAY' ) {
            die "“attachments” must be an arrayref, not “$opts_hr->{'attachments'}”!";
        }

        if ( grep { ref ne 'HASH' } @{ $opts_hr->{'attachments'} } ) {
            die 'each element of “attachments” must be a hashref!';
        }
    }

    if ( defined $opts_hr->{'x_headers'} && 'HASH' ne ref $opts_hr->{'x_headers'} ) {
        die '“x_headers” must be a hashref!';
    }

    return 1;
}

1;
