# NOTE: Derived from blib/lib/Data/Validate/URI.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package Data::Validate::URI;

#line 209 "blib/lib/Data/Validate/URI.pm (autosplit into blib/lib/auto/Data/Validate/URI/_test_uri.al)"
# -------------------------------------------------------------------------------

sub _test_uri {
	# 1 = HTTP only
	# 2 = HTTPS only
	# 3 = both HTTP and HTTPS are allowed
	my $allowed_scheme = shift;
	my $value = shift;
	my $options = shift // {};
	
	return unless is_uri($value);
	
	my($scheme, $authority, $path, $query, $fragment) = _split_uri($value);
	
	return unless $scheme;
	
	if($allowed_scheme == 1) {
		return unless lc($scheme) eq 'http';
	} elsif ($allowed_scheme == 2) {
		return unless lc($scheme) eq 'https'
	} elsif ($allowed_scheme == 3) {
		return unless lc($scheme) =~ m/^https?$/;
	} else {
		return;
	}
	
	# fully-qualified URIs must have an authority section that is
	# a valid host
	return unless($authority);
	
	# allow a port component
	my($port) = $authority =~ /:(\d+)$/;
	$authority =~ s/:\d+$//;
	
	# modifying this to allow the (discouraged, but still legal) use of IP addresses
	unless(Data::Validate::Domain::is_domain($authority, $options) || Data::Validate::IP::is_ipv4($authority)){
		return;
	}
	
	# re-assemble the URL per section 5.3 in RFC 3986
	my $out = $scheme . ':';
	$out .= '//' . $authority;
	
	$out .= ':' . $port if $port;
	
	$out .= $path;
	
	if(defined $query && length($query)){
		$out .= '?' . $query;
	}
	if(defined $fragment && length($fragment)){
		$out .= '#' . $fragment;
	}
	
	return $out;
}

# end of Data::Validate::URI::_test_uri
1;
