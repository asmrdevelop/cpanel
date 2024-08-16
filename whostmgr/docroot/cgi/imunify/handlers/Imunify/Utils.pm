package Imunify::Utils;



use strict;
use warnings FATAL => 'all';
use File::Temp;
use MIME::Base64;

use DBI;
use DBI qw(:sql_types);
use Data::Dumper;

use Cpanel::SafeRun::Errors ();
use Cpanel::JSON;
use Imunify::Render;
use Imunify::Config;

# use CGI::Carp qw(fatalsToBrowser); # uncomment to debug 500 error

sub execute {
    my ($action, $data, $isWHM) = @_;
    my $tmp = $isWHM ? File::Temp->new(DIR => '/var/imunify360/tmp') : File::Temp->new();
    $tmp->write(encode_base64(Cpanel::JSON::SafeDump($data), ''));
    $tmp->flush();
    my $command = join ' ', (Imunify::Config->COMMAND_WRAPPER_PATH, $action, $tmp->filename);
    return Cpanel::SafeRun::Errors::saferunallerrors(('/bin/sh', '-c', $command));
}

sub random {
    my ($len) = @_;
    my @chars = ('0'..'9', 'a'..'f');
    $len = 32 if !defined $len;
    my $string;

    while($len--){
        $string .= $chars[rand @chars];
    };

    return $string;
}

sub getPluginName {
    # check imunify360.conf file, since imunifyAV is dependency of IM360
    my $filename = '/etc/sysconfig/imunify360/cpanel/imunify360.conf';
    if(-e $filename && -f _ ){
       return 'imunify360';
    }
    return 'ImunifyAV';
}

sub dump {
    my ($data) = @_;
    Imunify::Render::JSONHeader(Imunify::Render->HTTP_STATUS_OK, $data);
    print Dumper($data);
    exit 0;
}

sub escapeParams {
    my ($value) = @_;
    $value =~ s/'/'\\''/g;
    $value = "'".$value."'";
    return $value;
}

1;
