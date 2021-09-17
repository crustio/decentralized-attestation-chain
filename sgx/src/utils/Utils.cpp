#include "Utils.h"

static char *_hex_buffer = NULL;
static size_t _hex_buffer_size = 0;
const char _hextable[] = "0123456789abcdef";

/**
 * @description: Remove indicated character from string
 * @param data -> Reference to string
 * @param c -> Character to be removed
 */
void remove_char(std::string &data, char c)
{
    data.erase(std::remove(data.begin(), data.end(), c), data.end());
}

/**
 * @description: Change char to int
 * @param input -> Input char
 * @return: Corresponding int
 */
int char_to_int(char input)
{
    if (input >= '0' && input <= '9')
        return input - '0';
    if (input >= 'A' && input <= 'F')
        return input - 'A' + 10;
    if (input >= 'a' && input <= 'f')
        return input - 'a' + 10;
    return 0;
}

/**
 * @description: Convert hexstring to bytes array
 * @param src -> Source char*
 * @param len -> Source char* length
 * @return: Bytes array
 */
uint8_t *hexstring_to_bytes(const char *src, size_t len)
{
    if(len % 2 != 0)
    {
        return NULL;
    }

    uint8_t *p_target;
    uint8_t *target = (uint8_t*)malloc(len/2);
    memset(target, 0, len/2);
    p_target = target;
    while (*src && src[1])
    {
        *(target++) = (uint8_t)(char_to_int(*src) * 16 + char_to_int(src[1]));
        src += 2;
    }

    return p_target;
}

/**
 * @description: Print hexstring
 * @param vsrc -> Pointer to source data
 * @param len -> Source data length
 */
void print_hexstring(const void *vsrc, size_t len)
{
    const unsigned char *sp = (const unsigned char *)vsrc;
    size_t i;
    for (i = 0; i < len; ++i)
    {
        printf("%02x", sp[i]);
    }
}

/**
 * @description: Dehexstring data
 * @param dest -> Pointer to destination data
 * @param vsrc -> Pointer to source data
 * @param len -> Source data length
 * @return: status
 */
int from_hexstring(unsigned char *dest, const void *vsrc, size_t len)
{
    size_t i;
    const unsigned char *src = (const unsigned char *)vsrc;

    for (i = 0; i < len; ++i)
    {
        unsigned int v;
#ifdef _WIN32
        if (sscanf_s(&src[i * 2], "%2xhh", &v) == 0)
            return 0;
#else
        if (sscanf(reinterpret_cast<const char*>(&src[i * 2]), "%2xhh", &v) == 0)
            return 0;
#endif
        dest[i] = (unsigned char)v;
    }

    return 1;
}

/**
 * @description: Transform string to hexstring, thread safe
 * @param vsrc -> Pointer to original data buffer
 * @param len -> Original data buffer length
 * @return: Hexstringed data
 */
std::string hexstring(const void *vsrc, size_t len)
{
    size_t i;
    const unsigned char *src = (const unsigned char *)vsrc;
    char *hex_buffer = (char*)malloc(len * 2);
    if (hex_buffer == NULL)
    {
        return "";
    }
    memset(hex_buffer, 0, len * 2);
    char *bp;

    for (i = 0, bp = hex_buffer; i < len; ++i)
    {
        *bp = _hextable[src[i] >> 4];
        ++bp;
        *bp = _hextable[src[i] & 0xf];
        ++bp;
    }

    std::string ret = std::string(hex_buffer, len * 2);
    free(hex_buffer);

    return ret;
}

/**
 * @description: Numeral to hexstring
 * @param num -> Numeral
 * @return: Hex string
 */
std::string num_to_hexstring(size_t num)
{
    std::string ans;
    char buf[32];
    memset(buf, 0, 32);
    sprintf(buf, "%lx", num);

    ans.append(buf);

    return ans;
}

EC_KEY *key_from_sgx_ec256 (sgx_ec256_public_t *k)
{
	EC_KEY *key= NULL;

	error_type= e_none;

	BIGNUM *gx= NULL;
	BIGNUM *gy= NULL;

	/* Get gx and gy as BIGNUMs */

	if ( (gx= BN_lebin2bn((unsigned char *) k->gx, sizeof(k->gx), NULL)) == NULL ) {
		error_type= e_crypto;
		goto cleanup;
	}

	if ( (gy= BN_lebin2bn((unsigned char *) k->gy, sizeof(k->gy), NULL)) == NULL ) {
		error_type= e_crypto;
		goto cleanup;
	}

	key= EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
	if ( key == NULL ) {
		error_type= e_crypto;
		goto cleanup;
	}

	if ( ! EC_KEY_set_public_key_affine_coordinates(key, gx, gy) ) {
		EC_KEY_free(key);
		key= NULL;
		error_type= e_crypto;
		goto cleanup;
	}


cleanup:
	if ( gy != NULL ) BN_free(gy);
	if ( gx != NULL ) BN_free(gx);

	return key;
}
