/****************
 * # NETWORK.TF *
 ****************/
/*************************************
 * # FETCH AZS IN THE CURRENT REGION *
 *************************************/
data "aws_availability_zones" "available" {
}

resource "aws_vpc" "main" {
  cidr_block           = "172.17.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "FIU-VPC-${var.enviroment}"
  }
}

/*****************************************************************
 * # CREATE VAR.AZ_COUNT PRIVATE SUBNETS, EACH IN A DIFFERENT AZ *
 *****************************************************************/
resource "aws_subnet" "private" {
  count             = var.az_count
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  vpc_id            = aws_vpc.main.id
  tags = {
    Name = "FIU-Private-subnet-${var.enviroment}"
  }
}

/****************************************************************
 * # CREATE VAR.AZ_COUNT PUBLIC SUBNETS, EACH IN A DIFFERENT AZ *
 ****************************************************************/
resource "aws_subnet" "public" {
  count                   = var.az_count
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, var.az_count + count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  vpc_id                  = aws_vpc.main.id
  map_public_ip_on_launch = true
  tags = {
    Name = "FIU-Public-subnet-${var.enviroment}"
  }
}

resource "aws_db_subnet_group" "db-subnet" {
  name       = "db-subnet-group-${var.enviroment}"
  subnet_ids = ["${aws_subnet.public[0].id}", "${aws_subnet.public[1].id}"]
  depends_on = [aws_subnet.public, ]
}

# resource "aws_db_subnet_group" "db-subnet" {
#   name       = "db-subnet-group-${var.enviroment}"
#   subnet_ids = ["${aws_subnet.private[0].id}", "${aws_subnet.private[1].id}"]
#   depends_on = [aws_subnet.private, ]
# }

/********************************************
 * # INTERNET GATEWAY FOR THE PUBLIC SUBNET *
 ********************************************/
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "FIU-Public-subnet-IG-${var.enviroment}"
  }
}

/*****************************************************
 * # ROUTE THE PUBLIC SUBNET TRAFFIC THROUGH THE IGW *
 *****************************************************/
resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.main.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

/**************************************************************************************************
 * # CREATE A NAT GATEWAY WITH AN ELASTIC IP FOR EACH PRIVATE SUBNET TO GET INTERNET CONNECTIVITY *
 **************************************************************************************************/
resource "aws_eip" "gw" {
  count      = var.az_count
  vpc        = true
  depends_on = [aws_internet_gateway.gw]
}

resource "aws_nat_gateway" "gw" {
  count         = var.az_count
  subnet_id     = element(aws_subnet.public.*.id, count.index)
  allocation_id = element(aws_eip.gw.*.id, count.index)
  tags = {
    Name = "FIU-Private-subnet-NAT-${var.enviroment}"
  }
}

/***********************************************************************************************************************
 * # CREATE A NEW ROUTE TABLE FOR THE PRIVATE SUBNETS, MAKE IT ROUTE NON-LOCAL TRAFFIC THROUGH THE NAT GATEWAY TO THE INTERNET *
 ***********************************************************************************************************************/
resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = element(aws_nat_gateway.gw.*.id, count.index)
  }
  tags = {
    Name = "FIU-Private-subnet-Route-${var.enviroment}"
  }
}

/***********************************************************************************************************************
 * # EXPLICITLY ASSOCIATE THE NEWLY CREATED ROUTE TABLES TO THE PRIVATE SUBNETS (SO THEY DON'T DEFAULT TO THE MAIN ROUTE TABLE) *
 ***********************************************************************************************************************/
resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}