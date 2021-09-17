#ifndef _CRUST_UTILS_H_
#define _CRUST_UTILS_H_

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <sys/types.h>
#include <algorithm>
#include <string.h>
#include <string>

//#include <openssl/bio.h>
//#include <openssl/evp.h>
#include <openssl/ec.h>
#include <openssl/ecdsa.h>
#include <openssl/err.h>
#include <openssl/bn.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>

#include <sgx_key_exchange.h>

static enum _error_type {
	e_none,
	e_crypto,
	e_system,
	e_api
} error_type= e_none;

#ifdef __cplusplus
extern "C"
{
#endif

    int char_to_int(char input);
    uint8_t *hexstring_to_bytes(const char *src, size_t len);
    int from_hexstring(unsigned char *dest, const void *src, size_t len);
    void print_hexstring(const void *vsrc, size_t len);
    std::string hexstring(const void *vsrc, size_t len);
    std::string num_to_hexstring(size_t num);
    void remove_char(std::string &data, char c);
    EC_KEY *key_from_sgx_ec256 (sgx_ec256_public_t *k);

#ifdef __cplusplus
};
#endif

#endif /* !_CRUST_UTILS_H_ */
