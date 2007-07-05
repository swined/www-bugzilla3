package WWW::Bugzilla3;

use warnings;
use strict;

use Carp;
use RPC::XML;
use RPC::XML::Parser;
use LWP::UserAgent;
use HTTP::Cookies;

our $VERSION = '0.1.1';

=head1 NAME

WWW::Bugzilla3 - perl bindings for Bugzilla 3.0 API

=head1 VERSION

Version 0.1.1

=head1 SYNOPSIS

	use WWW::Bugzilla3;

	my $bz = new WWW::Bugzilla3(site => 'bugz.somesite.org');
	$bz->login('user@host.org', 'PaSsWoRd');
	...

=head1 FUNCTIONS

=cut

sub _xstr($) { new RPC::XML::string(shift) }

sub _xdie($) {
	my $rs = shift;
	croak $rs unless ref $rs;
	croak "Error " . $rs->value->{faultCode}->value .
		": " . $rs->value->{faultString}->value . "\n"
		if $rs->is_fault;
}

sub _post($$) {
	my ($self, $u, $c) = @_;
        my $wrq = new HTTP::Request(POST => $u);
        $wrq->content($c);
        my $wrs = $self->{useragent}->request($wrq);
	return $wrs->content;
}

sub _prepare_xml_request($$) {
	my ($m, $v) = @_;
	my $st = new RPC::XML::struct($v);
	my $rq = new RPC::XML::request($m, $st);
	return $rq->as_string;
}

sub _xml_request($$$) {
	my ($self, $m, $v) = @_;
	my $rt = $self->_post($self->{xmlrpc}, _prepare_xml_request($m, $v));
	my $rs = (new RPC::XML::Parser)->parse($rt);
	_xdie $rs;
	return $rs;
}

=head2 new()

	Creates new Bugzilla3 object.
	 
=cut

sub new($%) {
	my ($class, %param) = @_;
	%param = { } unless %param;
	croak "Cannot create Bugzilla3 object without 'site'\n" unless $param{site};
	$param{site} = "http://" . $param{site} unless $param{site} =~ /^http:\/\//;
	$param{site} .= "/" unless $param{site} =~ /\/$/;
	$param{xmlrpc} = $param{site} . 'xmlrpc.cgi';
	$param{useragent} = new LWP::UserAgent;
	$param{useragent}->cookie_jar(new HTTP::Cookies);
	bless \%param, $class;
	return \%param;
}

=head2 login(login, password)

	Logs into bugzilla. Returns id of successfully logged in user. 
	
=cut

sub login($$$) {
	my ($self, $l, $p, $r) = @_;
	my $rs = $self->_xml_request(
		'User.login', 
		{ 
			'login' => _xstr $l, 
			'password' => _xstr $p,
		});
	return $rs->value->{id}->value;
}

=head2 logout()

	Logs out. Does nothing if you are not logged in.
	
=cut

sub logout($) {
	my ($self) = @_;
	$self->_xml_request(
		'User.logout', 
		{ });
	return undef;
}

=head2 offer_account_by_email(email)

	Sends an email to the user, offering to create an account. The user will have to click on a URL in the email, and choose their password and real name.
	
=cut

sub offer_account_by_email($$) {
	my ($self, $m) = @_;
	$self->_xml_request(
		'User.offer_account_by_email',
		{ 
			email => _xstr $m,
		});
	return undef;
}

=head2 create_user(email, full_name, password)

	Creates a user account directly in Bugzilla, password and all. Instead of this, you should use "offer_account_by_email" when possible, because that makes sure that the email address specified can actually receive an email. This function does not check that. Returns id of newly created user.
	
=cut

sub create_user($$$$) {
	my ($self, $m, $n, $p) = @_;
	my $rs = $self->_xml_request(
		'User.create',
		{
			email => _xstr $m,
			full_name => _xstr $n,
			password => _xstr $p,
		});
	return $rs->value->{id}->value;
}

=head2 get_selectable_products()

	Returns an array of the ids of the products the user can search on.	
	
=cut

sub get_selectable_products($) {
	my ($self) = @_;
	my $rs = $self->_xml_request(
		'Product.get_selectable_products',
		{ });
	return @{$rs->value->{ids}->value};
}

=head2 get_enterable_products()

	Returns an array of the ids of the products the user can enter bugs against.
	
=cut

sub get_enterable_products($) {
	my ($self) = @_;
	my $rs = $self->_xml_request(
		'Product.get_enterable_products',
		{ });
	return @{$rs->value->{ids}->value};
}

=head2 get_accessible_products()

	Returns an array of the ids of the products the user can search or enter bugs against.	
	
=cut

sub get_accessible_products($) {
	my ($self) = @_;
	my $rs = $self->_xml_request(
		'Product.get_accessible_products',
		{ });
	return @{$rs->value->{ids}->value};
}

=head2 get_products(ids)

	Returns an array of hashes. Each hash describes a product, and has the following items: id, name, description, and internals. The id item is the id of the product. The name item is the name of the product. The description is the description of the product. Finally, the internals is an internal representation of the product.
	Note, that if the user tries to access a product that is not in the list of accessible products for the user, or a product that does not exist, that is silently ignored, and no information about that product is returned.
	
=cut

sub get_products($@) {
	my ($self, @ids) = @_;
	my $rs = $self->_xml_request(
		'Product.get_products',
		{
			'ids' => new RPC::XML::array(
				map { new RPC::XML::int($_) } @ids
			),
		});
	return @{$rs->value->{products}->value};
}

=head2 version()

	Returns bugzilla version.
	
=cut

sub version($) {
	my ($self) = @_;
	my $rs = $self->_xml_request(
		'Bugzilla.version',
		{});
	return $rs->value->{version}->value;
}

=head2 timezone()

	Returns the timezone of the server Bugzilla is running on. This is important because all dates/times that the webservice interface returns will be in this timezone. 
	
=cut

sub timezone($) {
	my ($self) = @_;
	my $rs = $self->_xml_request(
		'Bugzilla.timezone',
		{});
	return $rs->value->{timezone}->value;
}

=head2 legal_values(field, product_id)

	Returns an array of values that are allowed for a particular field.
	
=cut

sub legal_values($$$) {
	my ($self, $f, $p) = @_;
	my $rs = $self->_xml_request(
		'Bug.legal_values',
		{
			field => _xstr $f,
			product_id => new RPC::XML::int($p),
		});
	return @{$rs->value->{'values'}->value};
}

=head2 get_bugs(ids)

	Gets information about particular bugs in the database. ids is an array of numbers and strings. 
	If an element in the array is entirely numeric, it represents a bug_id from the Bugzilla database to fetch. If it contains any non-numeric characters, it is considered to be a bug alias instead, and the bug with that alias will be loaded.
	Note that it's possible for aliases to be disabled in Bugzilla, in which case you will be told that you have specified an invalid bug_id if you try to specify an alias. (It will be error 100.)
	Returns an array of hashes. Each hash contains the following items:
	id - The numeric bug_id of this bug.
	alias - The alias of this bug. If there is no alias or aliases are disabled in this Bugzilla, this will be an empty string.
	summary - The summary of this bug.
	creation_time - When the bug was created.
	last_change_time - When the bug was last changed.
	
=cut

sub get_bugs($@) {
	my ($self, @ids) = @_;
		my $rs = $self->_xml_request(
			'Bug.get_bugs',
			{
				'ids' => new RPC::XML::array(
					map { new RPC::XML::int($_) } @ids
				),
			});
	return @{$rs->value->{bugs}->value};
}

=head2 create_bug(...) 

	This allows you to create a new bug in Bugzilla. If you specify any invalid fields, they will be ignored. If you specify any fields you are not allowed to set, they will just be set to their defaults or ignored.
	Some params must be set, or an error will be thrown. These params are marked Required.
	Some parameters can have defaults set in Bugzilla, by the administrator. If these parameters have defaults set, you can omit them. These parameters are marked Defaulted.
	Clients that want to be able to interact uniformly with multiple Bugzillas should always set both the params marked Required and those marked Defaulted, because some Bugzillas may not have defaults set for Defaulted parameters, and then this method will throw an error if you don't specify them.
	The descriptions of the parameters below are what they mean when Bugzilla is being used to track software bugs. They may have other meanings in some installations.
	product (string) Required - The name of the product the bug is being filed against. 
	component (string) Required - The name of a component in the product above. 
	summary (string) Required - A brief description of the bug being filed. 
	version (string) Required - A version of the product above; the version the bug was found in. 
	description (string) Defaulted - The initial description for this bug. Some Bugzilla installations require this to not be blank. 
	op_sys (string) Defaulted - The operating system the bug was discovered on. 
	platform (string) Defaulted - What type of hardware the bug was experienced on. 
	priority (string) Defaulted - What order the bug will be fixed in by the developer, compared to the developer's other bugs. 
	severity (string) Defaulted - How severe the bug is. 
	alias (string) - A brief alias for the bug that can be used instead of a bug number when accessing this bug. Must be unique in all of this Bugzilla. 
	assigned_to (username) - A user to assign this bug to, if you don't want it to be assigned to the component owner. 
	cc (array) - An array of usernames to CC on this bug. 
	qa_contact (username) - If this installation has QA Contacts enabled, you can set the QA Contact here if you don't want to use the component's default QA Contact. 
	status (string) - The status that this bug should start out as. Note that only certain statuses can be set on bug creation. 
	target_milestone (string) - A valid target milestone for this product.
	In addition to the above parameters, if your installation has any custom fields, you can set them just by passing in the name of the field and its value as a string.
	Returns one element, id. This is the id of the newly-filed bug.
	
=cut

sub create_bug($%) {
	my ($self, %p) = @_;
	my $params = { };
	foreach my $cp (%p) {
		if ($cp eq 'cc') {
			$params->{$cp} = new RPC::XML::array(map { _xstr $_ } $p{$cp});
			next;
		}
		$params->{$cp} = _xstr $p{$cp};
	}
	my $rs = $self->_xml_request('Bug.create', $params);
	return $rs->value->{id}->value;
}

1;

=head1 AUTHOR

Alexey Alexandrov, C<< <swined at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-www-bugzilla3 at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=WWW-Bugzilla3>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

	perldoc WWW::Bugzilla3

	You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/WWW-Bugzilla3>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/WWW-Bugzilla3>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=WWW-Bugzilla3>

=item * Search CPAN

L<http://search.cpan.org/dist/WWW-Bugzilla3>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2007 Alexey Alexandrov, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

