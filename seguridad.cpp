#include "seguridad.h"
#include <iostream>
#include <sstream>
#include <iomanip>
#include <vector>
#include <openssl/evp.h>
#include <string>
#include <openssl/rand.h>
#include <openssl/crypto.h>
#include <openssl/bio.h>
#include <openssl/buffer.h>

using namespace std;

string leerDatoSeguro(const string& mensaje) {
    string entrada;
    cout << mensaje;
    cin.clear();
    if (cin.peek() == '\n') {
        cin.ignore(); 
    }
    
    getline(cin, entrada);

    if (entrada == "xxx") {
        throw CancelarOperacionException();
    }

    return entrada;
}

string aplicarHash(const string& input) {
    EVP_MD_CTX *mdctx = EVP_MD_CTX_new();
    unsigned char hash[EVP_MAX_MD_SIZE];
    unsigned int length = 0;

    if (mdctx == nullptr) {
        return "";
    }

    if (EVP_DigestInit_ex(mdctx, EVP_sha256(), nullptr) != 1) {
        EVP_MD_CTX_free(mdctx);
        return "";
    }

    if (EVP_DigestUpdate(mdctx, input.c_str(), input.size()) != 1) {
        EVP_MD_CTX_free(mdctx);
        return "";
    }

    if (EVP_DigestFinal_ex(mdctx, hash, &length) != 1) {
        EVP_MD_CTX_free(mdctx);
        return "";
    }

    EVP_MD_CTX_free(mdctx);

    stringstream ss;
    for (unsigned int i = 0; i < length; ++i) {
        ss << hex << setw(2) << setfill('0') << static_cast<int>(hash[i]);
    }
    return ss.str();
}

// Base64 helpers using OpenSSL BIO
static string base64_encode(const unsigned char* input, int length) {
    BIO *bmem = nullptr;
    BIO *b64 = nullptr;
    BUF_MEM *bptr = nullptr;

    b64 = BIO_new(BIO_f_base64());
    BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
    bmem = BIO_new(BIO_s_mem());
    b64 = BIO_push(b64, bmem);
    BIO_write(b64, input, length);
    BIO_flush(b64);
    BIO_get_mem_ptr(b64, &bptr);

    string out(bptr->data, bptr->length);
    BIO_free_all(b64);
    return out;
}

static vector<unsigned char> base64_decode(const string &input) {
    BIO *b64 = BIO_new(BIO_f_base64());
    BIO *bmem = BIO_new_mem_buf(input.data(), input.size());
    BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
    bmem = BIO_push(b64, bmem);

    vector<unsigned char> out(input.size());
    int decoded_len = BIO_read(bmem, out.data(), input.size());
    if (decoded_len <= 0) {
        out.clear();
    } else {
        out.resize(decoded_len);
    }
    BIO_free_all(bmem);
    return out;
}

bool generar_hash_pbkdf2(const std::string &password, std::string &out_serializado) {
    const int SALT_LEN = 16;
    const int ITER = 100000;
    const int DK_LEN = 32;

    unsigned char salt[SALT_LEN];
    if (RAND_bytes(salt, SALT_LEN) != 1) return false;

    vector<unsigned char> dk(DK_LEN);
    if (!PKCS5_PBKDF2_HMAC(password.c_str(), password.size(), salt, SALT_LEN, ITER, EVP_sha256(), DK_LEN, dk.data())) {
        return false;
    }

    string salt_b64 = base64_encode(salt, SALT_LEN);
    string dk_b64 = base64_encode(dk.data(), DK_LEN);

    out_serializado = "pbkdf2$" + to_string(ITER) + "$" + salt_b64 + "$" + dk_b64;
    return true;
}

bool verificarPassword(const std::string &password, const std::string &stored, std::string *out_rehash) {
    if (stored.rfind("pbkdf2$", 0) == 0) {
        // formato: pbkdf2$iter$salt_b64$hash_b64
        vector<string> parts;
        string tmp;
        std::istringstream iss(stored);
        while (std::getline(iss, tmp, '$')) parts.push_back(tmp);
        if (parts.size() != 4) return false;
        int iter = stoi(parts[1]);
        vector<unsigned char> salt = base64_decode(parts[2]);
        vector<unsigned char> hash = base64_decode(parts[3]);
        if (salt.empty() || hash.empty()) return false;

        vector<unsigned char> dk(hash.size());
        if (!PKCS5_PBKDF2_HMAC(password.c_str(), password.size(), salt.data(), salt.size(), iter, EVP_sha256(), dk.size(), dk.data())) {
            return false;
        }

        // tiempo-constante comparison
        if (CRYPTO_memcmp(dk.data(), hash.data(), dk.size()) == 0) return true;
        return false;
    } else {
        // legacy: stored is hex of SHA256(password)
        string legacy = aplicarHash(password);
        if (legacy == stored) {
            if (out_rehash) {
                string newhash;
                if (generar_hash_pbkdf2(password, newhash)) {
                    *out_rehash = newhash;
                }
            }
            return true;
        }
        return false;
    }
}