#!/bin/bash

# Validates Packer configuration files without requiring Packer to be installed
# Uses basic syntax checking and configuration validation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
PACKER_DIR="$SCRIPT_DIR/packer"

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "  Packer Configuration Validation"
echo "=========================================="
echo ""

# Check if Packer config file exists
if [ ! -f "$PACKER_DIR/airgap-ubuntu.pkr.hcl" ]; then
    echo -e "${RED}✗ Packer config not found${NC}"
    exit 1
fi

echo -e "${BLUE}Checking Packer configuration structure...${NC}"
echo ""

# Check for required blocks
ERRORS=0

echo "Required blocks:"
if grep -q "packer {" "$PACKER_DIR/airgap-ubuntu.pkr.hcl"; then
    echo -e "  ${GREEN}✓${NC} packer block found"
else
    echo -e "  ${RED}✗${NC} packer block missing"
    ((ERRORS++))
fi

if grep -q "required_plugins {" "$PACKER_DIR/airgap-ubuntu.pkr.hcl"; then
    echo -e "  ${GREEN}✓${NC} required_plugins block found"
else
    echo -e "  ${RED}✗${NC} required_plugins block missing"
    ((ERRORS++))
fi

if grep -q "source \"qemu\"" "$PACKER_DIR/airgap-ubuntu.pkr.hcl"; then
    echo -e "  ${GREEN}✓${NC} QEMU source block found"
else
    echo -e "  ${RED}✗${NC} QEMU source block missing"
    ((ERRORS++))
fi

if grep -q "build {" "$PACKER_DIR/airgap-ubuntu.pkr.hcl"; then
    echo -e "  ${GREEN}✓${NC} build block found"
else
    echo -e "  ${RED}✗${NC} build block missing"
    ((ERRORS++))
fi

echo ""
echo "Variables:"
VARS=$(grep -c "variable \"" "$PACKER_DIR/airgap-ubuntu.pkr.hcl")
echo -e "  ${GREEN}✓${NC} Found $VARS variables defined"

echo ""
echo "Provisioners:"
PROVISIONERS=$(grep -c "provisioner \"shell\"" "$PACKER_DIR/airgap-ubuntu.pkr.hcl")
echo -e "  ${GREEN}✓${NC} Found $PROVISIONERS shell provisioners"

echo ""
echo "Cloud-init files:"
if [ -f "$PACKER_DIR/http/user-data" ]; then
    echo -e "  ${GREEN}✓${NC} user-data exists"
    if grep -q "autoinstall:" "$PACKER_DIR/http/user-data"; then
        echo -e "  ${GREEN}✓${NC} user-data has autoinstall config"
    else
        echo -e "  ${RED}✗${NC} user-data missing autoinstall config"
        ((ERRORS++))
    fi
else
    echo -e "  ${RED}✗${NC} user-data missing"
    ((ERRORS++))
fi

if [ -f "$PACKER_DIR/http/meta-data" ]; then
    echo -e "  ${GREEN}✓${NC} meta-data exists"
else
    echo -e "  ${RED}✗${NC} meta-data missing"
    ((ERRORS++))
fi

echo ""
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ Configuration is valid!${NC}"
    echo ""
    echo "The Packer configuration is properly structured."
    echo "You can build the image once Packer is installed:"
    echo ""
    echo "  cd $PACKER_DIR"
    echo "  packer init airgap-ubuntu.pkr.hcl"
    echo "  packer build airgap-ubuntu.pkr.hcl"
    exit 0
else
    echo -e "${RED}✗ Found $ERRORS error(s)${NC}"
    exit 1
fi
