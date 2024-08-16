package Cpanel::CPAN::Net::DAV::Server;

# Removed as per cPanel policy
#use strict;
#use warnings;
use HTTP::Response ();
use HTTP::Request  ();
use File::Spec     ();
use URI            ();
use URI::Escape qw(uri_unescape);
our $VERSION = '1.29';

our %implemented = (
    options  => 1,
    put      => 1,
    get      => 1,
    head     => 1,
    post     => 1,
    delete   => 1,
    trace    => 1,
    mkcol    => 1,
    propfind => 1,
    copy     => 1,
    lock     => 1,
    unlock   => 1,
    move     => 1
);

sub new {
    my ($class) = @_;
    my $self = {};
    bless $self, $class;
    return $self;
}

sub filesys {
    if ( $_[1] ) {
        $_[0]->{'filesys'} = $_[1];
    }
    else {
        return $_[0]->{'filesys'};
    }
}

sub run {
    my ( $self, $request, $response ) = @_;

    my $fs = $self->filesys || die 'Boom';

    my $method = $request->method;
    my $path   = uri_unescape $request->uri->path;

    if ( !defined $response ) {
        $response = HTTP::Response->new;
    }

    $method = lc $method;
    if ( $implemented{$method} ) {
        $response->code(200);
        $response->message('OK');

        $response = $self->$method( $request, $response );
        $response->header( 'Content-Length' => length( $response->content ) );
    }
    else {

        # Saying it isn't implemented is better than crashing!
        warn "$method not implemented\n";
        $response->code(501);
        $response->message('Not Implemented');
    }
    return $response;
}

sub options {
    my ( $self, $request, $response ) = @_;
    $response->header( 'DAV'           => '1,2,<http://apache.org/dav/propset/fs/1>' );    # Nautilus freaks out
    $response->header( 'MS-Author-Via' => 'DAV' );                                         # Nautilus freaks out
    $response->header( 'Allow'         => join( ',', map { uc } keys %implemented ) );
    $response->header( 'Content-Type'  => 'httpd/unix-directory' );
    $response->header( 'Keep-Alive'    => 'timeout=15, max=96' );
    return $response;
}

sub head {
    my ( $self, $request, $response ) = @_;
    my $path = uri_unescape $request->uri->path;
    my $fs   = $self->filesys;

    if ( $fs->test( "f", $path ) && $fs->test( "r", $path ) ) {
        my $fh = $fs->open_read($path);
        $fs->close_read($fh);
        $response->last_modified( $fs->modtime($path) );
    }
    elsif ( $fs->test( "d", $path ) ) {

        # a web browser, then
        my @files = $fs->list($path);
        $response->header( 'Content-Type' => 'text/html; charset="utf-8"' );
    }
    else {
        $response = HTTP::Response->new( 404, "NOT FOUND", $response->headers );
    }
    return $response;
}

sub lock {
    my ( $self, $request, $response ) = @_;
    my $path = uri_unescape $request->uri->path;
    my $fs   = $self->filesys;

    $fs->lock($path);

    return $response;
}

sub unlock {
    my ( $self, $request, $response ) = @_;
    my $path = uri_unescape $request->uri->path;
    my $fs   = $self->filesys;

    $fs->unlock($path);

    return $response;
}

1;
