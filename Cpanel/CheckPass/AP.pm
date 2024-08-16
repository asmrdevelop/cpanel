package Cpanel::CheckPass::AP;

# cpanel12 - CheckPass/AP.pm
#
# This file is covered by the (this file only)
# "THE BEER-WARE LICENSE" (Revision 42):
# <phk@login.dknet.dk> wrote this file.  As long as you retain this notice you
# can do whatever you want with this stuff. If we meet some day, and you think
# this stuff is worth it, you can buy me a beer in return.   Poul-Henning Kamp
#
# based on Crypt::PasswdMD5
#
# http://cpanel.net

use Crypt::Passwd::XS  ();
use Cpanel::LoadModule ();

our $VERSION = '1.3';

$Cpanel::CheckPass::AP::Magic = '$apr1$';

sub checkpassword {
    my ( $password, $cryptedpassword ) = @_;
    if ( $cryptedpassword eq "" || $cryptedpassword =~ /^\!/ || $cryptedpassword =~ /^\*/ ) { return (0); }

    return 0 if !defined $password || !defined $cryptedpassword || $password eq '' || $cryptedpassword eq '';

    if ( Crypt::Passwd::XS::crypt( $password, $cryptedpassword ) eq $cryptedpassword ) {
        return 1;
    }

    return (0);
}

sub new_md5_object {
    Cpanel::LoadModule::load_perl_module('Digest::MD5');
    return Digest::MD5->new();
}

sub apache_md5_crypt {
    my ( $pw, $salt ) = @_;
    my $passwd;

    $salt =~ s/^\Q$Cpanel::CheckPass::AP::Magic//;    # Take care of the magic string if

    # if present.

    $salt =~ s/^(.*)\$.*$/$1/;                        # Salt can have up to 8 chars...
    $salt = substr( $salt, 0, 8 );

    my $ctx = new_md5_object();

    # Here we start the calculation
    $ctx->add($pw);                                   # Original password...
    $ctx->add($Cpanel::CheckPass::AP::Magic);         # ...our magic string...
    $ctx->add($salt);                                 # ...the salt...

    my $final = new_md5_object();
    $final->add($pw);
    $final->add($salt);
    $final->add($pw);
    $final = $final->digest;

    for ( my $pl = length($pw); $pl > 0; $pl -= 16 ) {
        $ctx->add( substr( $final, 0, $pl > 16 ? 16 : $pl ) );
    }

    # Now the 'weird' xform

    for ( my $i = length($pw); $i; $i >>= 1 ) {
        if ( $i & 1 ) { $ctx->add( pack( "C", 0 ) ); }

        # This comes from the original version,
        # where a memset() is done to $final
        # before this loop.
        else { $ctx->add( substr( $pw, 0, 1 ) ); }
    }

    $final = $ctx->digest;

    # The following is supposed to make
    # things run slower. In perl, perhaps
    # it'll be *really* slow!

    for ( my $i = 0; $i < 1000; $i++ ) {
        my $ctx1 = new_md5_object();
        if   ( $i & 1 ) { $ctx1->add($pw); }
        else            { $ctx1->add( substr( $final, 0, 16 ) ); }
        if   ( $i % 3 ) { $ctx1->add($salt); }
        if   ( $i % 7 ) { $ctx1->add($pw); }
        if   ( $i & 1 ) { $ctx1->add( substr( $final, 0, 16 ) ); }
        else            { $ctx1->add($pw); }
        $final = $ctx1->digest;
    }

    # Final xform

    $passwd = '';
    $passwd .= to64( int( unpack( "C", ( substr( $final, 0, 1 ) ) ) << 16 ) | int( unpack( "C", ( substr( $final, 6,  1 ) ) ) << 8 ) | int( unpack( "C", ( substr( $final, 12, 1 ) ) ) ), 4 );
    $passwd .= to64( int( unpack( "C", ( substr( $final, 1, 1 ) ) ) << 16 ) | int( unpack( "C", ( substr( $final, 7,  1 ) ) ) << 8 ) | int( unpack( "C", ( substr( $final, 13, 1 ) ) ) ), 4 );
    $passwd .= to64( int( unpack( "C", ( substr( $final, 2, 1 ) ) ) << 16 ) | int( unpack( "C", ( substr( $final, 8,  1 ) ) ) << 8 ) | int( unpack( "C", ( substr( $final, 14, 1 ) ) ) ), 4 );
    $passwd .= to64( int( unpack( "C", ( substr( $final, 3, 1 ) ) ) << 16 ) | int( unpack( "C", ( substr( $final, 9,  1 ) ) ) << 8 ) | int( unpack( "C", ( substr( $final, 15, 1 ) ) ) ), 4 );
    $passwd .= to64( int( unpack( "C", ( substr( $final, 4, 1 ) ) ) << 16 ) | int( unpack( "C", ( substr( $final, 10, 1 ) ) ) << 8 ) | int( unpack( "C", ( substr( $final, 5,  1 ) ) ) ), 4 );
    $passwd .= to64( int( unpack( "C", substr( $final, 11, 1 ) ) ), 2 );

    $final = '';
    return ( $Cpanel::CheckPass::AP::Magic . $salt . '$' . $passwd );

}

sub to64 {
    my $itoa64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    my ( $v, $n ) = @_;
    my $ret = '';
    while ( --$n >= 0 ) {
        $ret .= substr( $itoa64, $v & 0x3f, 1 );
        $v >>= 6;
    }
    $ret;
}

sub getsalt {
    my ($cpass) = @_;
    ( $cpass =~ /^\$(?:apr)?1\$(.+)\$.*/ ) and return $1;
    ( $cpass =~ /^(..).*/ )                and return $1;
}

1;
